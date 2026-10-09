import AppKit
import Foundation
import Testing
@testable import OpenIslandApp

/// The rule these tests hold: nothing that stays on screen may animate
/// forever on the main thread. A SwiftUI timeline or a repeating SwiftUI
/// animation redraws its whole window on every tick, and the Settings window
/// burned more than half a CPU core for as long as its Personalization tab
/// was open. Motion that never ends belongs on a Core Animation layer.
@MainActor
@Suite struct EnergyPolicyTests {
    private static let sourceRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/OpenIslandApp", isDirectory: true)

    /// Every Swift file under a folder of the app's sources, or the one file.
    private static func swiftFiles(under relativePath: String) throws -> [URL] {
        let url = sourceRoot.appendingPathComponent(relativePath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            Issue.record("Missing source path: \(relativePath)")
            return []
        }
        guard isDirectory.boolValue else { return [url] }
        let found = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        return found
    }

    /// Code only: a comment may name what the code must not use.
    private static func code(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    // MARK: Settings and the welcome tour

    @Test(arguments: [
        "Views/Settings",
        "Views/AppearanceSettingsPane.swift",
        "Views/IslandHaloPreview.swift",
        "Nook/Views/NookPersonalizationSections.swift",
        "Onboarding",
    ])
    func settingsAndTheTourHoldNoEndlessSwiftUIAnimation(path: String) throws {
        let files = try Self.swiftFiles(under: path)
        #expect(!files.isEmpty)
        for file in files {
            let code = try Self.code(of: file)
            for banned in ["phaseAnimator", "repeatForever", "TimelineView(.animation"] {
                #expect(!code.contains(banned), "\(file.lastPathComponent) uses \(banned)")
            }
        }
    }

    @Test func theVisualizerRunsOnNoTimeline() throws {
        let file = try #require(try Self.swiftFiles(under: "Nook/Views/NookMediaViews.swift").first)
        let code = try Self.code(of: file)
        let start = try #require(code.range(of: "struct NookBarVisualizer"))
        let end = try #require(code.range(of: "struct NookMediaCard"))

        #expect(!code[start.lowerBound..<end.lowerBound].contains("TimelineView"))
    }

    @Test func theClosedIslandPreviewComesToRest() {
        #expect((1...12).contains(ClosedPreviewSection.autoCycleSteps))
    }

    // MARK: The visualizer's layers

    private func makeBars(isMoving: Bool, isPlaying: Bool = true, count: Int = 4) -> NookBarVisualizerLayerView {
        let view = NookBarVisualizerLayerView(frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        view.update(isMoving: isMoving, isPlaying: isPlaying, barCount: count, height: 20, color: NSColor.white.cgColor)
        view.layout()
        return view
    }

    @Test func playingBarsMoveOnLayerLoopsThatNeverEnd() throws {
        let view = makeBars(isMoving: true)

        #expect(view.bars.count == 4)
        for (index, bar) in view.bars.enumerated() {
            let loop = try #require(bar.animation(forKey: NookBarVisualizerLayerView.loopKey) as? CABasicAnimation)
            #expect(loop.keyPath == "bounds.size.height")
            #expect(loop.repeatCount == .infinity)
            #expect(loop.autoreverses)
            #expect(loop.duration == NookBarVisualizerLayerView.riseDuration(index: index))
            #expect(bar.opacity == Float(0.9))
        }
        // Each bar has its own pace.
        let paces = Set(view.bars.indices.map { NookBarVisualizerLayerView.riseDuration(index: $0) })
        #expect(paces.count == 4)
    }

    @Test func theSameStateTwiceLeavesTheLoopsRunning() throws {
        let view = makeBars(isMoving: true)
        let before = try view.bars.map { try #require($0.animation(forKey: NookBarVisualizerLayerView.loopKey)) }

        view.update(isMoving: true, isPlaying: true, barCount: 4, height: 20, color: NSColor.white.cgColor)
        view.layout()
        // A new tint is not a reason to start over either.
        view.update(isMoving: true, isPlaying: true, barCount: 4, height: 20, color: NSColor.red.cgColor)

        let after = try view.bars.map { try #require($0.animation(forKey: NookBarVisualizerLayerView.loopKey)) }
        #expect(zip(before, after).allSatisfy { $0 === $1 })
        #expect(view.bars.first?.backgroundColor == NSColor.red.cgColor)
    }

    @Test func pausedOrHiddenBarsHoldStill() {
        let paused = makeBars(isMoving: false, isPlaying: false)
        #expect(paused.bars.allSatisfy { $0.animation(forKey: NookBarVisualizerLayerView.loopKey) == nil })
        #expect(paused.bars.allSatisfy { $0.opacity == Float(0.4) })
        #expect(paused.bars.allSatisfy { $0.bounds.height == CGFloat(20) * NookBarVisualizer.pausedLevel })

        // Playing behind the opened island: no loops, the look of playing.
        let hidden = makeBars(isMoving: false, isPlaying: true)
        #expect(hidden.bars.allSatisfy { $0.animation(forKey: NookBarVisualizerLayerView.loopKey) == nil })
        #expect(hidden.bars.allSatisfy { $0.opacity == Float(0.9) })

        // Starting and stopping takes the loops on and off.
        hidden.update(isMoving: true, isPlaying: true, barCount: 4, height: 20, color: NSColor.white.cgColor)
        #expect(hidden.bars.allSatisfy { $0.animation(forKey: NookBarVisualizerLayerView.loopKey) != nil })
        hidden.update(isMoving: false, isPlaying: false, barCount: 4, height: 20, color: NSColor.white.cgColor)
        #expect(hidden.bars.allSatisfy { $0.animation(forKey: NookBarVisualizerLayerView.loopKey) == nil })
    }

    @Test func theBarsSitInARowCenteredInTheView() {
        let view = makeBars(isMoving: false, isPlaying: false, count: 4)
        let rowWidth = NookBarVisualizer.width(barCount: 4)

        #expect(rowWidth == CGFloat(4 * 3 + 3 * 2))
        #expect(NookBarVisualizer.width(barCount: 0) == CGFloat(0))
        let left = (view.bounds.width - rowWidth) / 2
        #expect(view.bars.first?.frame.minX == left)
        #expect(view.bars.last?.frame.maxX == left + rowWidth)
        #expect(view.bars.allSatisfy { $0.position.y == view.bounds.midY })
        #expect(view.hitTest(CGPoint(x: 5, y: 5)) == nil)
    }

    @Test func aChangeInTheNumberOfBarsRebuildsThem() {
        let view = makeBars(isMoving: true, count: 4)

        view.update(isMoving: true, isPlaying: true, barCount: 6, height: 20, color: NSColor.white.cgColor)

        #expect(view.bars.count == 6)
        #expect(view.layer?.sublayers?.count == 6)
        #expect(view.bars.allSatisfy { $0.animation(forKey: NookBarVisualizerLayerView.loopKey) != nil })
    }

    // MARK: Still pictures

    @Test func aStillPictureOfTheBarsIsUnevenWhilePlayingAndFlatWhilePaused() {
        let playing = (0..<4).map { NookBarVisualizer.stillLevel(index: $0, isPlaying: true) }
        let paused = (0..<4).map { NookBarVisualizer.stillLevel(index: $0, isPlaying: false) }

        #expect(Set(playing).count == 4)
        #expect(playing.allSatisfy { $0 >= NookBarVisualizer.lowLevel && $0 <= 1 })
        #expect(paused.allSatisfy { $0 == NookBarVisualizer.pausedLevel })
    }

    @Test func aStillPictureOfAFlashShowsItsPeak() {
        let flash = IslandHaloState(
            color: .approval, motion: .flash(token: 1, peak: 0.9, duration: 1.2), restOpacity: 0.2, radius: 12, drop: 2
        )
        let steady = IslandHaloState(color: .approval, motion: .steady, restOpacity: 0.4, radius: 12, drop: 2)

        #expect(IslandHaloStillGlow.opacity(for: flash) == 0.9)
        #expect(IslandHaloStillGlow.opacity(for: steady) == 0.4)
    }
}
