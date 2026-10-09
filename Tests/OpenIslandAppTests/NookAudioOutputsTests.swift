import Foundation
import Testing
@testable import OpenIslandApp

/// The speaker picker on the now-playing card, on hardware that exists only
/// in memory.
@MainActor
@Suite struct NookAudioOutputsTests {
    private typealias Samples = NookMediaSamples

    private static func hardware() -> FakeAudioHardware {
        FakeAudioHardware(
            devices: [Samples.loopback, Samples.display, Samples.airPods, Samples.speakers],
            defaultID: Samples.speakers.id,
            systemID: Samples.speakers.id
        )
    }

    // MARK: Rules

    @Test func theMacsOwnSpeakersComeFirstAndVirtualDevicesLast() {
        let sorted = NookAudioOutputRules.sorted([Samples.loopback, Samples.display, Samples.airPods, Samples.speakers])
        #expect(sorted == [Samples.speakers, Samples.airPods, Samples.display, Samples.loopback])
    }

    @Test func outputsOfOneKindSortByName() {
        let beta = NookAudioOutput(id: 1, name: "beta", kind: .usb)
        let alpha = NookAudioOutput(id: 2, name: "Alpha", kind: .usb)
        #expect(NookAudioOutputRules.sorted([beta, alpha]) == [alpha, beta])
    }

    @Test func eachOutputGetsASymbolThatSaysWhatItIs() {
        #expect(NookAudioOutputRules.symbol(for: Samples.speakers) == "speaker.wave.2.fill")
        #expect(NookAudioOutputRules.symbol(for: Samples.airPods) == "airpodspro")
        #expect(NookAudioOutputRules.symbol(for: Samples.display) == "display")
        #expect(NookAudioOutputRules.symbol(for: Samples.loopback) == "waveform")
        // Bluetooth alone does not say speaker or headphones. The name does.
        let soundbar = NookAudioOutput(id: 7, name: "HT-A5000", kind: .bluetooth)
        let headphones = NookAudioOutput(id: 8, name: "WH-1000XM5", kind: .bluetooth)
        let airPodsMax = NookAudioOutput(id: 9, name: "AirPods Max", kind: .bluetooth)
        #expect(NookAudioOutputRules.symbol(for: soundbar) == "hifispeaker.fill")
        #expect(NookAudioOutputRules.symbol(for: headphones) == "headphones")
        #expect(NookAudioOutputRules.symbol(for: airPodsMax) == "airpodsmax")
        #expect(NookAudioOutputRules.symbol(for: NookAudioOutput(id: 10, name: "Kitchen", kind: .airPlay)) == "airplayaudio")
    }

    @Test func alertSoundsFollowOnlyWhenTheyCameOutOfTheSamePlace() {
        #expect(NookAudioOutputRules.alertsFollowOutput(systemID: 95, defaultID: 95))
        #expect(!NookAudioOutputRules.alertsFollowOutput(systemID: 140, defaultID: 95))
        #expect(!NookAudioOutputRules.alertsFollowOutput(systemID: nil, defaultID: 95))
        #expect(!NookAudioOutputRules.alertsFollowOutput(systemID: 95, defaultID: nil))
    }

    // MARK: The picker

    @Test func startingListsTheOutputsAndMarksTheCurrentOne() {
        let hardware = Self.hardware()
        let outputs = NookAudioOutputs(hardware: hardware)
        #expect(outputs.devices.isEmpty)

        outputs.start()
        outputs.start()

        #expect(hardware.startCount == 1)
        #expect(outputs.devices == [Samples.speakers, Samples.airPods, Samples.display, Samples.loopback])
        #expect(outputs.currentID == Samples.speakers.id)
        #expect(outputs.current == Samples.speakers)
    }

    @Test func pickingAnOutputSwitchesToItAndTakesTheAlertSoundsAlong() {
        let hardware = Self.hardware()
        let outputs = NookAudioOutputs(hardware: hardware)
        outputs.start()

        outputs.select(Samples.airPods.id)

        #expect(hardware.defaultSets == [Samples.airPods.id])
        #expect(hardware.systemSets == [Samples.airPods.id])
        #expect(outputs.currentID == Samples.airPods.id)
        #expect(outputs.failedID == nil)
    }

    @Test func alertSoundsThatWentElsewhereStayWhereTheyWere() {
        let hardware = Self.hardware()
        hardware.systemID = Samples.display.id
        let outputs = NookAudioOutputs(hardware: hardware)
        outputs.start()

        outputs.select(Samples.airPods.id)

        #expect(hardware.defaultSets == [Samples.airPods.id])
        #expect(hardware.systemSets.isEmpty)
        #expect(hardware.systemID == Samples.display.id)
    }

    @Test func pickingTheCurrentOutputDoesNothing() {
        let hardware = Self.hardware()
        let outputs = NookAudioOutputs(hardware: hardware)
        outputs.start()

        outputs.select(Samples.speakers.id)

        #expect(hardware.defaultSets.isEmpty)
        #expect(hardware.systemSets.isEmpty)
    }

    @Test func anOutputThatRefusesIsMarkedAndTheOldOneStaysCurrent() {
        let hardware = Self.hardware()
        hardware.refusedOutputs = [Samples.display.id]
        let outputs = NookAudioOutputs(hardware: hardware)
        outputs.start()

        outputs.select(Samples.display.id)

        #expect(outputs.failedID == Samples.display.id)
        #expect(outputs.currentID == Samples.speakers.id)
        #expect(hardware.systemSets.isEmpty)

        // A switch that works clears the mark.
        outputs.select(Samples.airPods.id)
        #expect(outputs.failedID == nil)
        #expect(outputs.currentID == Samples.airPods.id)
    }

    @Test func openingThePickerAgainForgetsASwitchThatFailedLastTime() {
        let hardware = Self.hardware()
        hardware.refusedOutputs = [Samples.display.id]
        let outputs = NookAudioOutputs(hardware: hardware)
        outputs.start()
        outputs.select(Samples.display.id)
        #expect(outputs.failedID == Samples.display.id)

        // The list is closed and opened again, with the same outputs.
        outputs.beginPicking()

        #expect(outputs.failedID == nil)
        #expect(outputs.currentID == Samples.speakers.id)
        #expect(outputs.devices.count == 4)
    }

    @Test func theListFollowsOutputsThatComeAndGo() {
        let hardware = Self.hardware()
        hardware.refusedOutputs = [Samples.display.id]
        let outputs = NookAudioOutputs(hardware: hardware)
        outputs.start()
        outputs.select(Samples.display.id)
        #expect(outputs.failedID == Samples.display.id)

        // The AirPods go back in their case.
        hardware.devices.removeAll { $0 == Samples.airPods }
        hardware.emit(.devices)

        #expect(outputs.devices == [Samples.speakers, Samples.display, Samples.loopback])
        #expect(outputs.failedID == nil)

        // They connect again and macOS moves the sound to them.
        hardware.devices.append(Samples.airPods)
        hardware.defaultID = Samples.airPods.id
        hardware.emit(.devices)
        hardware.emit(.defaultOutput)

        #expect(outputs.devices.contains(Samples.airPods))
        #expect(outputs.currentID == Samples.airPods.id)
    }

    @Test func aVolumeChangeDoesNotRereadTheOutputs() {
        let hardware = Self.hardware()
        let outputs = NookAudioOutputs(hardware: hardware)
        outputs.start()

        hardware.devices = []
        hardware.emit(.level)

        #expect(outputs.devices.count == 4)
    }
}
