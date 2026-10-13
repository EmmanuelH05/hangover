import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Shuffle and repeat on the music card. A player either reports them with
/// the rest of what is playing, or is one of the two that are asked by
/// script (Spotify, Music), or gets no buttons. No test here runs a script:
/// each hands in a runner of its own.
@MainActor
@Suite struct NowPlayingModesTests {
    private static func state(_ bundle: String, title: String = "Song", _ more: [String: Any] = [:]) -> NowPlayingState {
        NowPlayingState(payload: ["bundleIdentifier": bundle, "title": title, "playing": true].merging(more) { $1 })!
    }

    /// Records what was run and answers with the replies it was given.
    private final class Scripted: @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [NookPlayerScriptReply]
        private(set) var ran: [String] = []

        init(_ replies: [NookPlayerScriptReply]) { self.replies = replies }

        func run(_ source: String) -> NookPlayerScriptReply {
            lock.lock()
            defer { lock.unlock() }
            ran.append(source)
            return replies.isEmpty ? .failed : replies.removeFirst()
        }
    }

    /// Waits for the script on its way and any that was waiting behind it.
    private static func settle(_ service: MediaRemoteService) async {
        while let task = service.playerScripts?.inFlight { await task.value }
    }

    private static func service(_ scripted: Scripted, defaults: UserDefaults = MemoryDefaults()) -> (MediaRemoteService, () -> [[String]]) {
        var launched: [[String]] = []
        let scripts = NookPlayerScripts(defaults: defaults) { scripted.run($0) }
        let service = MediaRemoteService(commandLauncher: { launched.append($0); return true }, playerScripts: scripts)
        return (service, { launched })
    }

    @Test func aReportCarriesTheModesAndAnUnknownNumberIsNoMode() {
        let both = Self.state("com.example.player", ["shuffleMode": 3, "repeatMode": 2])
        #expect(both.shuffle == .tracks)
        #expect(both.repeating == .track)
        #expect(Self.state("com.example.player").shuffle == nil)
        #expect(Self.state("com.example.player", ["shuffleMode": 0, "repeatMode": 9]).repeating == nil)
        #expect(Self.state("com.example.player", ["shuffleMode": 0]).shuffle == nil)
    }

    @Test func repeatGoesAllThenOneThenOff() {
        #expect(NowPlayingRepeat.off.next == .playlist)
        #expect(NowPlayingRepeat.playlist.next == .track)
        #expect(NowPlayingRepeat.track.next == .off)
        #expect(NowPlayingRepeat.track.symbol == "repeat.1")
        #expect(NowPlayingShuffle.albums.toggled == .off)
        #expect(NowPlayingShuffle.off.toggled == .tracks)
    }

    @Test func aPlayerThatReportsItsModesIsToldTheOneToGoTo() {
        let scripted = Scripted([])
        let (service, launched) = Self.service(scripted)
        service.apply(Self.state("com.example.player", ["shuffleMode": 1, "repeatMode": 3]))
        #expect(service.offersModes)
        service.toggleShuffle()
        service.cycleRepeat()
        #expect(launched() == [["shuffle", "3"], ["repeat", "2"]])
        #expect(scripted.ran.isEmpty)
    }

    @Test func aPlayerInABrowserGetsNoButtons() {
        let (service, _) = Self.service(Scripted([]))
        service.apply(Self.state("com.apple.WebKit.GPU"))
        #expect(!service.offersModes)
        #expect(service.shuffle == nil)
    }

    @Test func spotifyIsAskedOnlyAfterAPressAndThenOnEveryNewTrack() async {
        let scripted = Scripted([.said("true,off,true\n"), .said("true,all,true"), .said("false,all,true")])
        let defaults = MemoryDefaults()
        let (service, launched) = Self.service(scripted, defaults: defaults)
        let scripts = service.playerScripts!

        service.apply(Self.state("com.spotify.client"))
        #expect(service.offersModes)
        #expect(scripted.ran.isEmpty, "nothing is sent to a player before a press")
        #expect(service.shuffle == nil)

        service.toggleShuffle()
        await Self.settle(service)
        #expect(scripted.ran.count == 1)
        #expect(scripted.ran[0].contains("tell application id \"com.spotify.client\""))
        #expect(scripted.ran[0].contains("set shuffling to not shuffling"))
        #expect(service.shuffle == .tracks)
        #expect(service.repeating == .off)
        #expect(scripts.hasAsked(.spotify))
        #expect(launched().isEmpty, "the adapter is not sent a blind toggle as well")

        service.cycleRepeat()
        await Self.settle(service)
        #expect(scripted.ran[1].contains("set repeating to not repeating"))
        #expect(service.repeating == .playlist)

        service.apply(Self.state("com.spotify.client", title: "Next song"))
        await Self.settle(service)
        #expect(scripted.ran.count == 3)
        #expect(!scripted.ran[2].contains("to not"), "a new track only reads")
        #expect(service.shuffle == .off)
    }

    @Test func aRefusalDimsTheButtonsAndKeepsNoMode() async {
        let scripted = Scripted([.refused])
        let (service, _) = Self.service(scripted)
        service.apply(Self.state("com.apple.Music"))
        service.cycleRepeat()
        await Self.settle(service)
        #expect(service.modesRefused)
        #expect(service.repeating == nil)
        #expect(scripted.ran[0].contains("tell application id \"com.apple.Music\""))
    }

    /// Spotify greys out its own two buttons for a station. Ours follow, and
    /// a press then only looks again: it switches nothing.
    @Test func aPlayerThatHasThemSwitchedOffDimsTheButtonsAndAPressOnlyLooksAgain() async {
        let scripted = Scripted([.said("false,off,false"), .said("false,off,false"), .said("false,off,true")])
        let (service, _) = Self.service(scripted)
        service.apply(Self.state("com.spotify.client"))
        service.toggleShuffle()
        await Self.settle(service)
        #expect(service.modesUnavailable)
        #expect(service.shuffle == .off)

        service.cycleRepeat()
        await Self.settle(service)
        #expect(!scripted.ran[1].contains("to not"), "nothing is switched while the player says no")
        service.toggleShuffle()
        await Self.settle(service)
        #expect(!service.modesUnavailable)
        #expect(NookScriptedPlayer.spotify.script(.read).contains("repeating enabled as text"))
    }

    @Test func aSecondPressWaitsForTheFirst() async {
        let scripted = Scripted([.said("true,off,true")])
        let (service, _) = Self.service(scripted)
        service.apply(Self.state("com.spotify.client"))
        service.toggleShuffle()
        service.toggleShuffle()
        await Self.settle(service)
        #expect(scripted.ran.count == 1)
    }

    @Test func aPressDuringAReadRunsWhenTheReadIsBack() async {
        let scripted = Scripted([.said("false,off,true"), .said("true,off,true")])
        let defaults = MemoryDefaults()
        defaults.set(true, forKey: NookPlayerScripts.askedKey(.spotify))
        let (service, _) = Self.service(scripted, defaults: defaults)
        service.apply(Self.state("com.spotify.client"))
        service.toggleShuffle()
        await Self.settle(service)
        #expect(scripted.ran.count == 2)
        #expect(!scripted.ran[0].contains("to not"))
        #expect(scripted.ran[1].contains("set shuffling to not shuffling"))
        #expect(service.shuffle == .tracks)
    }

    @Test func aPlayerThatNeverAnsweredIsNotReadAgain() async {
        let scripted = Scripted([.failed])
        let (service, _) = Self.service(scripted)
        service.apply(Self.state("com.spotify.client"))
        service.toggleShuffle()
        await Self.settle(service)
        #expect(service.playerScripts?.hasAsked(.spotify) == false)
        service.apply(Self.state("com.spotify.client", title: "Next song"))
        service.refreshModes()
        await Self.settle(service)
        #expect(scripted.ran.count == 1, "no read goes out before the player has answered a press")
    }

    @Test func aPauseOrTheCardShowingReadsAgain() async {
        let scripted = Scripted([.said("true,off,true"), .said("false,off,true"), .said("false,all,true")])
        let (service, _) = Self.service(scripted)
        service.apply(Self.state("com.spotify.client"))
        service.toggleShuffle()
        await Self.settle(service)
        service.apply(Self.state("com.spotify.client", ["playing": false]))
        await Self.settle(service)
        #expect(service.shuffle == .off)
        service.refreshModes()
        await Self.settle(service)
        #expect(service.repeating == .playlist)
        #expect(scripted.ran.count == 3)
    }

    @Test func aServiceWithoutScriptsAsksNoPlayer() {
        var launched: [[String]] = []
        let service = MediaRemoteService(commandLauncher: { launched.append($0); return true })
        service.apply(Self.state("com.spotify.client"))
        #expect(!service.offersModes)
        #expect(service.playerScripts == nil)
    }

    @Test func everyScriptNamesItsOwnPlayerAndEndsWithWhereItStands() {
        for player in NookScriptedPlayer.allCases {
            for action in [NookScriptedPlayer.Action.read, .toggleShuffle, .cycleRepeat] {
                let script = player.script(action)
                #expect(script.hasPrefix("if application id \"\(player.rawValue)\" is running then\ntell application id \"\(player.rawValue)\"\n"))
                #expect(script.hasSuffix("\nend tell\nelse\nerror \"not running\"\nend if"))
                #expect(script.contains("return ("))
            }
        }
        #expect(!NookScriptedPlayer.spotify.script(.read).contains("to not"))
        #expect(NookScriptedPlayer.music.script(.cycleRepeat).contains("set song repeat to one"))
    }

    @Test func aReplyIsReadOrLeftAlone() {
        #expect(NookScriptedPlayer.modes(fromReply: "true,one,true\n") == NookPlayerModes(shuffle: .tracks, repeating: .track))
        #expect(NookScriptedPlayer.modes(fromReply: "false,all,false")
            == NookPlayerModes(shuffle: .off, repeating: .playlist, isAvailable: false))
        #expect(NookScriptedPlayer.modes(fromReply: "") == nil)
        #expect(NookScriptedPlayer.modes(fromReply: "true,all") == nil)
        #expect(NookScriptedPlayer.modes(fromReply: "maybe,all,true") == nil)
        #expect(NookScriptedPlayer.modes(fromReply: "true,sometimes,true") == nil)
        #expect(NookScriptedPlayer.modes(fromReply: "true,all,perhaps") == nil)
    }

    @Test func aReportThatOnlyChangesAModeKeepsTheClock() {
        let (service, _) = Self.service(Scripted([]))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock: [String: Any] = ["elapsedTime": 40.0, "timestamp": "2027-01-15T08:00:00Z", "duration": 200.0]
        service.apply(Self.state("com.example.player", clock.merging(["shuffleMode": 1]) { $1 }), now: start)
        let before = service.state?.position(at: start.addingTimeInterval(5))
        service.apply(Self.state("com.example.player", clock.merging(["shuffleMode": 3]) { $1 }), now: start.addingTimeInterval(5))
        #expect(service.shuffle == .tracks)
        #expect(service.state?.position(at: start.addingTimeInterval(5)) == before)
    }

    @Test func theSamplePlayerSwitchesBothAndSendsNothingOutside() {
        var launched: [[String]] = []
        let player = DemoPlayer(startsPlaying: false)
        let service = MediaRemoteService(commandLauncher: { launched.append($0); return true }, sample: player)
        service.start()
        #expect(service.offersModes)
        #expect(service.shuffle == .off)
        service.toggleShuffle()
        #expect(service.shuffle == .tracks)
        service.cycleRepeat()
        service.cycleRepeat()
        #expect(service.repeating == .track)
        #expect(launched.isEmpty)
    }

    /// The card at its three sizes with shuffle on and one song on repeat.
    /// Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1` to write the PNGs to
    /// `output/render/music/`. Nothing here shows a window.
    @Test func theButtonsAreParkedInEveryBuild() {
        #expect(!NookModeButtonsOffer.isOffered)
        #expect(NookModeButtonsOffer.$override.withValue(true) { NookModeButtonsOffer.isOffered })
    }

    @Test func theCardDrawsBothButtonsAtEverySize() throws {
        try NookModeButtonsOffer.$override.withValue(true) { try drawTheCardAtEverySize() }
    }

    private func drawTheCardAtEverySize() throws {
        for (size, width) in [(NookWidgetSize.small, 237.0), (.medium, 484.0), (.large, 484.0)] {
            let player = DemoPlayer(startsPlaying: false, elapsed: 84, now: { Date(timeIntervalSince1970: 1_800_000_000) })
            let media = MediaRemoteService(sample: player)
            media.start()
            media.toggleShuffle()
            media.cycleRepeat()
            media.cycleRepeat()
            let nook = NookModel(media: media, defaults: MemoryDefaults(), looksForImportedGIF: false, asksMacOSForAccess: false)
            let renderer = ImageRenderer(
                content: NookMediaCard(nook: nook)
                    .environment(\.nookWidgetSize, size)
                    .frame(width: width, height: NookMediaCard.height(for: size))
                    .padding(8)
                    .background(Color.black)
                    .environment(\.colorScheme, .dark)
                    .environment(\.nookDrawsStill, true)
            )
            renderer.scale = 2
            let image = try #require(renderer.cgImage, "no picture for the \(size.rawValue) card")
            #expect(image.width == Int((width + 16) * 2))
            guard ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" else { continue }
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("output/render/music", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("modes-\(size.rawValue).png"))
        }
    }
}
