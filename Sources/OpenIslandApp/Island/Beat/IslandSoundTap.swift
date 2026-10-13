import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Whether this Mac can follow a song at all (D56).
enum IslandBeatSupport {
    /// The process tap came with macOS 14.2. On 14.0 and 14.1 the switch
    /// is not shown.
    static var isAvailable: Bool {
        if #available(macOS 14.2, *) { true } else { false }
    }

    /// The real listener, or nil on a Mac too old for it.
    @MainActor
    static func makeListener() -> (any IslandBeatListening)? {
        if #available(macOS 14.2, *) { return IslandSystemBeatListener() }
        return nil
    }
}

/// Why the tap could not be built. The number is Core Audio's own status.
enum IslandSoundTapError: Error, Equatable {
    case tap(OSStatus)
    case format(OSStatus)
    case unsupportedFormat
    case outputDevice(OSStatus)
    case aggregateDevice(OSStatus)
    case ioBlock(OSStatus)
    case start(OSStatus)
}

/// The shape of the tap's own stream, read from the tap itself
/// (`kAudioTapPropertyFormat`). Every buffer the sound queue is handed is
/// checked against it, and one that does not match is never read.
struct IslandTapLayout: Equatable, Sendable {
    /// More channels than this is not a mix anybody listens to.
    static let mostChannels = 8

    var sampleRate: Double
    var channels: Int
    /// True when one buffer holds the channels side by side, false when
    /// each channel has a buffer of its own.
    var isInterleaved: Bool

    init(sampleRate: Double, channels: Int, isInterleaved: Bool) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.isInterleaved = isInterleaved
    }

    /// Nil for anything but 32-bit float samples in a sane count of channels.
    init?(format: AudioStreamBasicDescription) {
        guard format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32,
              (1...Self.mostChannels).contains(Int(format.mChannelsPerFrame)) else { return nil }
        self.init(
            sampleRate: format.mSampleRate,
            channels: Int(format.mChannelsPerFrame),
            isInterleaved: format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        )
    }

    var bufferCount: Int { isInterleaved ? 1 : channels }
    var channelsInABuffer: Int { isInterleaved ? channels : 1 }
}

/// How the tap's device is put together (D56), as plain values.
enum IslandSoundTapPlan {
    /// The device takes its clock from the output in use, as a sub-device,
    /// but only when that output has no input of its own. A USB headset or
    /// any other output with a microphone would bring the microphone's
    /// streams into the device's input list. Then the device is built from
    /// the tap alone, and a microphone is never part of it.
    static func usesOutputAsSubDevice(outputHasInputs: Bool) -> Bool {
        !outputHasInputs
    }

    /// The description of the aggregate device. With no `outputUID` it
    /// names no sub-device at all.
    static func deviceDescription(name: String, uid: String, tapUID: String, outputUID: String?) -> [String: Any] {
        var description: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapUID,
                ],
            ],
        ]
        if let outputUID {
            description[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
            description[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: outputUID]]
        }
        return description
    }
}

/// A Core Audio process tap on everything the Mac plays (D56): a global
/// stereo mix, not muted, private to this app, read through an aggregate
/// device made for it. Nothing is recorded: each buffer goes to the handler
/// and is gone. No microphone and no screen capture are involved.
///
/// Building and tearing down wait on Core Audio, for tens of milliseconds
/// at times. They run on a serial queue of the tap's own, one after the
/// other, and never on the main actor. All of the tap's state is touched on
/// that queue only, which is why the class can be marked Sendable.
@available(macOS 14.2, *)
final class IslandSoundTap: @unchecked Sendable {
    /// Called on the sound queue with one buffer list and the tap's layout.
    typealias Handler = @Sendable (UnsafePointer<AudioBufferList>, IslandTapLayout) -> Void

    enum Event: Sendable {
        /// The tap runs. Sent after the first build and after every rebuild.
        case started(outputDelay: TimeInterval)
        /// It could not be built, or not be built again.
        case failed
    }

    /// The largest buffer the tap asks its device for. A beat is known at
    /// the end of the buffer that holds it, which makes a smaller buffer a
    /// light that is closer to the beat.
    static let wantedBufferFrames: UInt32 = 512

    private static let name = "Hangover beat"
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    private let control = DispatchQueue(label: "hangover.beat.control", qos: .utility)
    private let sound = DispatchQueue(label: "hangover.beat.tap", qos: .utility)

    // Everything below is touched on `control` only.
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var handler: Handler?
    private var report: (@Sendable (Event) -> Void)?
    private var outputWatch: AudioObjectPropertyListenerBlock?
    private var rateWatch: AudioObjectPropertyListenerBlock?
    private var watchedDevice = AudioObjectID(kAudioObjectUnknown)
    /// The output and its rate the running tap was built for.
    private var builtFor: (device: AudioObjectID, rate: Float64)?

    /// Asks for the tap to be built and started. `report` hears how it
    /// went, and again after every rebuild, on the control queue.
    func start(handler: @escaping Handler, report: @escaping @Sendable (Event) -> Void) {
        control.async { [self] in
            teardown()
            self.handler = handler
            self.report = report
            watchDefaultOutput()
            buildAndReport()
        }
    }

    /// Asks for the block to be stopped and the device and the tap to be
    /// destroyed. Nothing is kept paused.
    func stop() {
        control.async { [self] in
            handler = nil
            report = nil
            unwatchDefaultOutput()
            unwatchRate()
            teardown()
        }
    }

    // MARK: Building

    private func buildAndReport() {
        guard let handler, let report else { return }
        do {
            report(.started(outputDelay: try build(handler: handler)))
        } catch {
            print("[IslandBeat] the tap was not built: \(error)")
            teardown()
            report(.failed)
        }
    }

    private func teardown() {
        if deviceID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(deviceID, procID)
                AudioDeviceDestroyIOProcID(deviceID, procID)
            }
            AudioHardwareDestroyAggregateDevice(deviceID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        deviceID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        builtFor = nil
    }

    /// Builds the tap, the device around it and the block that reads it,
    /// and starts them. Returns the speaker's delay.
    private func build(handler: @escaping Handler) throws -> TimeInterval {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = Self.name
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(description, &tap)
        guard status == noErr, tap != kAudioObjectUnknown else { throw IslandSoundTapError.tap(status) }
        tapID = tap

        // The layout is the tap's own, asked of the tap. Whatever else the
        // device might hold, only buffers of this shape are ever read.
        guard let layout = IslandTapLayout(format: try Self.format(ofTap: tap)) else {
            throw IslandSoundTapError.unsupportedFormat
        }

        let output = try Self.defaultOutputDevice()
        let usesOutput = IslandSoundTapPlan.usesOutputAsSubDevice(outputHasInputs: Self.hasInputs(output))
        let deviceDescription = IslandSoundTapPlan.deviceDescription(
            name: Self.name,
            uid: UUID().uuidString,
            tapUID: description.uuid.uuidString,
            outputUID: usesOutput ? try Self.uid(of: output) : nil
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(deviceDescription as CFDictionary, &device)
        guard status == noErr, device != kAudioObjectUnknown else {
            throw IslandSoundTapError.aggregateDevice(status)
        }
        deviceID = device
        Self.askForSmallBuffers(on: device)

        var proc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&proc, device, sound) { _, input, _, _, _ in
            handler(input, layout)
        }
        guard status == noErr, let proc else { throw IslandSoundTapError.ioBlock(status) }
        procID = proc

        status = AudioDeviceStart(device, proc)
        guard status == noErr else { throw IslandSoundTapError.start(status) }

        builtFor = (output, Self.nominalRate(of: output))
        watchRate(of: output)
        return Self.outputDelay(of: output)
    }

    // MARK: Following the output

    /// Called on the control queue when the Mac's output or its sample
    /// rate changed. The tap is built again for what is true now: its
    /// device took its clock and its rate from the old output. A notice
    /// that changes nothing, which Core Audio also sends, builds nothing.
    private func outputChanged() {
        guard handler != nil else { return }
        if let builtFor, let output = try? Self.defaultOutputDevice(),
           builtFor.device == output, builtFor.rate == Self.nominalRate(of: output) {
            return
        }
        teardown()
        buildAndReport()
    }

    private func watchDefaultOutput() {
        guard outputWatch == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.outputChanged() }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        if AudioObjectAddPropertyListenerBlock(Self.system, &address, control, block) == noErr {
            outputWatch = block
        }
    }

    private func unwatchDefaultOutput() {
        guard let block = outputWatch else { return }
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectRemovePropertyListenerBlock(Self.system, &address, control, block)
        outputWatch = nil
    }

    private func watchRate(of device: AudioObjectID) {
        guard device != watchedDevice || rateWatch == nil else { return }
        unwatchRate()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.outputChanged() }
        var address = Self.address(kAudioDevicePropertyNominalSampleRate)
        if AudioObjectAddPropertyListenerBlock(device, &address, control, block) == noErr {
            rateWatch = block
            watchedDevice = device
        }
    }

    private func unwatchRate() {
        guard let block = rateWatch else { return }
        var address = Self.address(kAudioDevicePropertyNominalSampleRate)
        AudioObjectRemovePropertyListenerBlock(watchedDevice, &address, control, block)
        rateWatch = nil
        watchedDevice = AudioObjectID(kAudioObjectUnknown)
    }

    // MARK: Asking Core Audio

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func format(ofTap tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = Self.address(kAudioTapPropertyFormat)
        let status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format)
        guard status == noErr else { throw IslandSoundTapError.format(status) }
        return format
    }

    private static func defaultOutputDevice() throws -> AudioObjectID {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else {
            throw IslandSoundTapError.outputDevice(status)
        }
        return device
    }

    private static func uid(of device: AudioObjectID) throws -> String {
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = Self.address(kAudioDevicePropertyDeviceUID)
        let status = withUnsafeMutablePointer(to: &uid) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let uid else { throw IslandSoundTapError.outputDevice(status) }
        return uid.takeRetainedValue() as String
    }

    /// Whether a device has any input stream, which is where a microphone
    /// would be. A device that cannot be asked counts as having one.
    private static func hasInputs(_ device: AudioObjectID) -> Bool {
        var size: UInt32 = 0
        var address = Self.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return true }
        return size > 0
    }

    private static func nominalRate(of device: AudioObjectID) -> Float64 {
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        var address = Self.address(kAudioDevicePropertyNominalSampleRate)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr ? rate : 0
    }

    /// One 32-bit number of a device or a stream, and zero when it has none.
    private static func number(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        of object: AudioObjectID
    ) -> UInt32 {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = Self.address(selector, scope: scope)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : 0
    }

    /// The speaker's own delay: the device's latency, its safety offset,
    /// its first stream's latency and one buffer, on the output side.
    private static func outputDelay(of device: AudioObjectID) -> TimeInterval {
        var stream = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = Self.address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        // Only the first stream is asked for. A device with more than one
        // answers with as many as fit, and the first is the one that plays.
        _ = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &stream)

        return IslandBeatTiming.outputDelay(
            deviceLatency: number(kAudioDevicePropertyLatency, scope: kAudioObjectPropertyScopeOutput, of: device),
            safetyOffset: number(kAudioDevicePropertySafetyOffset, scope: kAudioObjectPropertyScopeOutput, of: device),
            streamLatency: stream == kAudioObjectUnknown
                ? 0
                : number(kAudioStreamPropertyLatency, scope: kAudioObjectPropertyScopeGlobal, of: stream),
            bufferFrames: number(kAudioDevicePropertyBufferFrameSize, scope: kAudioObjectPropertyScopeGlobal, of: device),
            sampleRate: nominalRate(of: device)
        )
    }

    /// Asks the tap's device for buffers of 512 frames when its own are
    /// larger. A device that will not have it keeps what it had.
    private static func askForSmallBuffers(on device: AudioObjectID) {
        let current = number(kAudioDevicePropertyBufferFrameSize, scope: kAudioObjectPropertyScopeGlobal, of: device)
        guard current > wantedBufferFrames else { return }
        var wanted = wantedBufferFrames
        var address = Self.address(kAudioDevicePropertyBufferFrameSize)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &wanted)
    }
}

/// Reads a buffer list of 32-bit float samples down to one channel, and
/// only when the list is exactly the tap's own (D56).
enum IslandBeatMixdown {
    private static let buffersOffset = MemoryLayout<AudioBufferList>.offset(of: \AudioBufferList.mBuffers) ?? 8

    private static func buffers(of list: UnsafePointer<AudioBufferList>) -> UnsafePointer<AudioBuffer> {
        (UnsafeRawPointer(list) + buffersOffset).assumingMemoryBound(to: AudioBuffer.self)
    }

    /// How many frames `list` holds when it is the tap's own stream, and
    /// nil when it is anything else: another count of buffers or channels,
    /// a buffer with no data, or sizes that do not agree. A list that is
    /// not the tap's, which is how a microphone would show up, is not read.
    static func frames(in list: UnsafePointer<AudioBufferList>, layout: IslandTapLayout) -> Int? {
        let count = Int(list.pointee.mNumberBuffers)
        guard count == layout.bufferCount else { return nil }
        let buffers = buffers(of: list)
        let bytesAFrame = MemoryLayout<Float>.size * layout.channelsInABuffer
        var frames = -1
        var index = 0
        while index < count {
            let buffer = buffers[index]
            let size = Int(buffer.mDataByteSize)
            guard Int(buffer.mNumberChannels) == layout.channelsInABuffer, buffer.mData != nil,
                  size % bytesAFrame == 0 else { return nil }
            if frames < 0 {
                frames = size / bytesAFrame
            } else if frames != size / bytesAFrame {
                return nil
            }
            index += 1
        }
        return max(frames, 0)
    }

    /// Writes the mean of the tap's channels for `count` frames, starting
    /// `offset` frames in, to `out`. The caller has checked the list with
    /// `frames(in:layout:)` and made room for `count` values. Accelerate
    /// does the adding: no loop here runs once a sample.
    static func mix(
        _ list: UnsafePointer<AudioBufferList>,
        layout: IslandTapLayout,
        from offset: Int,
        count: Int,
        into out: UnsafeMutablePointer<Float>
    ) {
        let buffers = buffers(of: list)
        let length = vDSP_Length(count)
        var share = 1 / Float(layout.channels)
        var channel = 0
        while channel < layout.channels {
            let buffer = layout.isInterleaved ? buffers[0] : buffers[channel]
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return }
            let stride = layout.isInterleaved ? layout.channels : 1
            let first = layout.isInterleaved ? data + offset * layout.channels + channel : data + offset
            if channel == 0 {
                vDSP_vsmul(first, stride, &share, out, 1, length)
            } else {
                vDSP_vsma(first, stride, &share, out, 1, out, 1, length)
            }
            channel += 1
        }
    }
}

/// Runs on the tap's sound queue: checks each buffer is the tap's own,
/// mixes it to mono, feeds the analyzer and hands the main actor a frame
/// when one is due.
///
/// Its state is touched only from that one serial queue, which is why it
/// can be marked Sendable without a lock. Its working memory is made once.
final class IslandBeatRelay: @unchecked Sendable {
    private let deliver: @MainActor (IslandBeatFrame) -> Void
    private let refuse: @MainActor () -> Void
    private let scratch = IslandBeatScratch()
    private var analyzer: IslandBeatAnalyzer?
    /// The rate the analyzer was made for. A new rate is a new analyzer:
    /// its hops, and with them the three a second limit, are counted in
    /// samples of the rate it was made with.
    private var analyzerRate: Double = 0
    private var throttle = IslandBeatThrottle()
    /// Time as the sound counts it: frames read over their rate.
    private var clock: TimeInterval = 0
    private var hasRefused = false
    /// Nothing is handed over before a sample that is not zero. The first
    /// frame the main actor gets means the tap hears real sound.
    private var hasHeardSound = false

    /// `refuse` is called once, when a buffer arrives that is not the tap's.
    init(
        deliver: @escaping @MainActor (IslandBeatFrame) -> Void,
        refuse: @escaping @MainActor () -> Void
    ) {
        self.deliver = deliver
        self.refuse = refuse
    }

    func take(_ list: UnsafePointer<AudioBufferList>, layout: IslandTapLayout) {
        guard !hasRefused else { return }
        guard let frames = IslandBeatMixdown.frames(in: list, layout: layout) else {
            hasRefused = true
            let refuse = refuse
            DispatchQueue.main.async {
                MainActor.assumeIsolated { refuse() }
            }
            return
        }
        guard frames > 0, let summary = read(list, layout: layout, frames: frames) else { return }
        if !hasHeardSound {
            guard !summary.isSilent else { return }
            hasHeardSound = true
        }
        guard let frame = throttle.take(summary, at: clock) else { return }
        let deliver = deliver
        DispatchQueue.main.async {
            MainActor.assumeIsolated { deliver(frame) }
        }
    }

    /// The analyzer's word on one checked buffer. Internal for the tests,
    /// which call it with lists they made.
    func read(_ list: UnsafePointer<AudioBufferList>, layout: IslandTapLayout, frames: Int) -> IslandBeatSummary? {
        if analyzer == nil || analyzerRate != layout.sampleRate {
            analyzer = IslandBeatAnalyzer(sampleRate: layout.sampleRate, bufferFrames: frames)
            analyzerRate = layout.sampleRate
        }
        guard var analyzer else { return nil }
        var summary: IslandBeatSummary?
        var offset = 0
        while offset < frames {
            let count = min(IslandBeatScratch.capacity, frames - offset)
            IslandBeatMixdown.mix(list, layout: layout, from: offset, count: count, into: scratch.samples)
            let part = analyzer.process(frames: count, in: scratch)
            summary = summary?.followed(by: part) ?? part
            offset += count
        }
        self.analyzer = analyzer
        clock += Double(frames) / analyzer.sampleRate
        return summary
    }

    /// For the tests: the analyzer in use and where its memory is.
    var analyzerInUse: IslandBeatAnalyzer? { analyzer }
    var scratchAddress: UnsafeMutablePointer<Float> { scratch.input }
}

/// The listener a real launch uses: the tap and the relay behind it.
@available(macOS 14.2, *)
@MainActor
final class IslandSystemBeatListener: IslandBeatListening {
    private let tap = IslandSoundTap()
    /// Counts the starts. Anything that comes back from an older one is
    /// dropped.
    private var run = 0

    private(set) var outputDelay: TimeInterval = 0

    func start(
        onFrame: @escaping @MainActor (IslandBeatFrame) -> Void,
        onFailure: @escaping @MainActor () -> Void
    ) {
        run += 1
        let run = run
        let relay = IslandBeatRelay(
            deliver: { [weak self] frame in
                guard let self, self.run == run else { return }
                onFrame(frame)
            },
            refuse: { [weak self] in
                self?.failed(run: run, onFailure)
            }
        )
        tap.start(handler: { list, layout in relay.take(list, layout: layout) }) { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.run == run else { return }
                    switch event {
                    case let .started(outputDelay):
                        self.outputDelay = outputDelay
                    case .failed:
                        self.failed(run: run, onFailure)
                    }
                }
            }
        }
    }

    func stop() {
        run += 1
        outputDelay = 0
        tap.stop()
    }

    private func failed(run: Int, _ onFailure: @MainActor () -> Void) {
        guard self.run == run else { return }
        stop()
        onFailure()
    }
}
