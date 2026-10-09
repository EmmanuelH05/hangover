import Foundation

/// How one photo booth session is paced. The numbers are a choice made
/// for this app, close to how event booths run, and not a standard.
struct NookPhotoBoothPlan: Equatable, Sendable {
    /// First countdown lengths the settings offer, in seconds.
    static let countdownChoices = [3, 5, 10]
    static let defaultCountdown = 5
    /// The countdown before every picture after the first.
    static let laterCountdownLimit = 3

    /// Pictures in one session.
    var shots: Int
    /// Numbers counted down before the first picture. The longest wait,
    /// which gives a hand time to leave the trackpad.
    var firstCountdown: Int
    /// Numbers counted down before each picture after the first.
    var laterCountdown: Int
    /// How long each number stays up.
    var beat: TimeInterval
    /// The "get ready" card before the first countdown.
    var getReady: TimeInterval
    /// How long the picture just taken is held on screen.
    var preview: TimeInterval
    /// The "next pose" card before the next countdown.
    var nextPose: TimeInterval

    init(
        shots: Int = 4,
        firstCountdown: Int = defaultCountdown,
        laterCountdown: Int? = nil,
        beat: TimeInterval = 1,
        getReady: TimeInterval = 1,
        preview: TimeInterval = 1.2,
        nextPose: TimeInterval = 0.8
    ) {
        let first = max(1, firstCountdown)
        self.shots = max(1, shots)
        self.firstCountdown = first
        self.laterCountdown = max(1, laterCountdown ?? min(first, Self.laterCountdownLimit))
        self.beat = max(0, beat)
        self.getReady = max(0, getReady)
        self.preview = max(0, preview)
        self.nextPose = max(0, nextPose)
    }

    /// The countdown that runs before a picture. Shots count from 1.
    func countdown(beforeShot shot: Int) -> Int {
        shot <= 1 ? firstCountdown : laterCountdown
    }
}

/// Where a session is.
enum NookPhotoBoothPhase: Equatable, Sendable {
    /// The card before the first countdown.
    case getReady
    /// A number is on screen before picture `shot`. Shots count from 1.
    case countdown(shot: Int, number: Int)
    /// Picture `shot` has been asked for and has not come back yet.
    case capturing(shot: Int)
    /// Picture `shot` is in and held on screen.
    case preview(shot: Int)
    /// The live picture is back, before the countdown to picture `shot`.
    case nextPose(shot: Int)
    /// Every picture is in and the strip is being put together.
    case composing
    /// The strip is ready.
    case done
}

/// What the booth must do when the session moves.
enum NookPhotoBoothEffect: Equatable, Sendable {
    /// A countdown number came up.
    case showNumber(Int)
    /// Take picture `shot` now.
    case capture(shot: Int)
    /// Put the strip together.
    case compose
}

/// One run of the booth as a plain value: a countdown, a picture, a look
/// at it, and again, then the strip. It owns no clock and no camera. The
/// booth tells it the time, and it answers with what to do.
///
/// Two rules live here and nowhere else. A picture is only ever asked for
/// by the step that follows the last countdown number, and a step never
/// ends before it has had its full time on screen: a clock that jumps
/// ahead moves the session one step, never past a countdown.
struct NookPhotoBoothSession: Equatable, Sendable {
    let plan: NookPhotoBoothPlan
    private(set) var phase: NookPhotoBoothPhase
    /// When the current phase began.
    private(set) var phaseStart: Date

    init(plan: NookPhotoBoothPlan, at now: Date) {
        self.plan = plan
        phase = .getReady
        phaseStart = now
    }

    /// Pictures that have come back.
    var shotsTaken: Int {
        switch phase {
        case .getReady: 0
        case let .countdown(shot, _), let .capturing(shot), let .nextPose(shot): shot - 1
        case let .preview(shot): shot
        case .composing, .done: plan.shots
        }
    }

    /// The picture being counted down to, taken or looked at.
    var currentShot: Int? {
        switch phase {
        case .getReady: 1
        case let .countdown(shot, _), let .capturing(shot), let .preview(shot), let .nextPose(shot): shot
        case .composing, .done: nil
        }
    }

    /// Moves the session at most one step, and only when the current step
    /// has had its full time.
    mutating func advance(to now: Date) -> [NookPhotoBoothEffect] {
        let elapsed = now.timeIntervalSince(phaseStart)
        switch phase {
        case .getReady:
            guard elapsed >= plan.getReady else { return [] }
            return startCountdown(beforeShot: 1, at: now)
        case let .countdown(shot, number):
            guard elapsed >= plan.beat else { return [] }
            if number > 1 {
                enter(.countdown(shot: shot, number: number - 1), at: now)
                return [.showNumber(number - 1)]
            }
            enter(.capturing(shot: shot), at: now)
            return [.capture(shot: shot)]
        case let .preview(shot):
            guard elapsed >= plan.preview else { return [] }
            if shot < plan.shots {
                enter(.nextPose(shot: shot + 1), at: now)
                return []
            }
            enter(.composing, at: now)
            return [.compose]
        case let .nextPose(shot):
            guard elapsed >= plan.nextPose else { return [] }
            return startCountdown(beforeShot: shot, at: now)
        case .capturing, .composing, .done:
            // These end when the camera or the composer reports back.
            return []
        }
    }

    /// The picture being waited for came back.
    mutating func pictureArrived(at now: Date) {
        guard case let .capturing(shot) = phase else { return }
        enter(.preview(shot: shot), at: now)
    }

    /// The strip is put together and saved.
    mutating func stripReady(at now: Date) {
        guard phase == .composing else { return }
        enter(.done, at: now)
    }

    private mutating func startCountdown(beforeShot shot: Int, at now: Date) -> [NookPhotoBoothEffect] {
        let number = plan.countdown(beforeShot: shot)
        enter(.countdown(shot: shot, number: number), at: now)
        return [.showNumber(number)]
    }

    private mutating func enter(_ next: NookPhotoBoothPhase, at now: Date) {
        phase = next
        phaseStart = now
    }
}
