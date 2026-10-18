import AppKit
import SwiftUI
import Testing
@testable import OpenIslandApp

/// A mailer that records instead of touching Mail or the clipboard.
@MainActor
private final class FakeMailer: FeedbackMailing {
    var canOpen = true
    var opened: [URL] = []
    var copied: [String] = []

    func canOpenMail(_ url: URL) -> Bool { canOpen }
    func open(_ url: URL) { opened.append(url) }
    func copy(_ text: String) { copied.append(text) }
}

private let fixedDetails = FeedbackDetails(version: "1.0.13", build: "1505", macOS: "26.4", model: "Mac15,12")

struct FeedbackDraftTests {
    @Test
    func subjectCarriesTheKindTag() {
        #expect(FeedbackDraft(kind: .bug, text: "It hangs").subject(appName: "Hangover") == "[Hangover Bug] It hangs")
        #expect(FeedbackDraft(kind: .idea, text: "Dark mode").subject(appName: "Hangover") == "[Hangover Idea] Dark mode")
        #expect(FeedbackDraft(kind: .other, text: "Hi").subject(appName: "Hangover") == "[Hangover Something else] Hi")
    }

    @Test
    func blankTextGivesOnlyTheTag() {
        #expect(FeedbackDraft(kind: .bug, text: "").subject(appName: "Hangover") == "[Hangover Bug]")
        #expect(FeedbackDraft(kind: .idea, text: " \n  \n").subject(appName: "Hangover") == "[Hangover Idea]")
    }

    @Test
    func subjectUsesTheFirstNonEmptyLineCutAtEighty() {
        let draft = FeedbackDraft(kind: .bug, text: "\nfirst line\nsecond")
        #expect(draft.subject(appName: "Hangover") == "[Hangover Bug] first line")
        let long = String(repeating: "a", count: 120)
        let cut = FeedbackDraft(kind: .bug, text: long).subject(appName: "Hangover")
        #expect(cut == "[Hangover Bug] " + String(repeating: "a", count: 80))
    }

    @Test
    func detailsLineReadsAsTheFrameDoes() {
        #expect(fixedDetails.line == "Version 1.0.13 (1505), macOS 26.4, Mac15,12")
    }

    @Test
    func currentDetailsHaveAModelIdentifier() {
        let details = FeedbackDetails.current()
        #expect(!details.model.isEmpty)
        #expect(!details.macOS.isEmpty)
    }

    @Test
    func bodyHasDetailsOnlyWhenOn() {
        var draft = FeedbackDraft(kind: .bug, text: "It hangs", includesDetails: true)
        #expect(draft.body(details: fixedDetails) == "It hangs\n\nVersion 1.0.13 (1505), macOS 26.4, Mac15,12")
        draft.includesDetails = false
        #expect(draft.body(details: fixedDetails) == "It hangs")
    }

    @Test
    func mailtoEncodesAddressSubjectAndBody() throws {
        let draft = FeedbackDraft(kind: .bug, text: "a & b + c\nline two", includesDetails: false)
        let url = try #require(draft.mailtoURL(to: "me@example.com", appName: "Hangover", details: fixedDetails))
        #expect(url.absoluteString == "mailto:me@example.com?subject=%5BHangover%20Bug%5D%20a%20%26%20b%20%2B%20c&body=a%20%26%20b%20%2B%20c%0D%0Aline%20two")
    }

    @Test
    func mailtoBodyCarriesDetailsAfterABlankLine() throws {
        let draft = FeedbackDraft(kind: .idea, text: "x", includesDetails: true)
        let url = try #require(draft.mailtoURL(to: "me@example.com", appName: "Hangover", details: fixedDetails))
        #expect(url.absoluteString.hasSuffix("&body=x%0D%0A%0D%0AVersion%201.0.13%20%281505%29%2C%20macOS%2026.4%2C%20Mac15%2C12"))
    }
}

@MainActor
struct FeedbackPresenterTests {
    private func make(_ mailer: FakeMailer) -> FeedbackPresenter {
        FeedbackPresenter(mailer: mailer, details: { fixedDetails })
    }

    @Test
    func sendOpensTheDraftWhenMailCanHandleIt() throws {
        let mailer = FakeMailer()
        let presenter = make(mailer)
        presenter.present(kind: .bug, text: "It hangs")
        presenter.send()

        #expect(mailer.opened.count == 1)
        #expect(mailer.opened.first?.scheme == "mailto")
        #expect(mailer.opened.first?.absoluteString.hasPrefix("mailto:\(AppBrand.feedbackAddress)?subject=") == true)
        #expect(mailer.copied.isEmpty)
        #expect(presenter.outcome == .opened)
        #expect(!presenter.isPresented)
    }

    @Test
    func sendCopiesTheBodyWhenNothingHandlesMail() {
        let mailer = FakeMailer()
        mailer.canOpen = false
        let presenter = make(mailer)
        presenter.present(kind: .bug, text: "It hangs")
        presenter.send()

        #expect(mailer.opened.isEmpty)
        #expect(mailer.copied == ["It hangs\n\nVersion 1.0.13 (1505), macOS 26.4, Mac15,12"])
        #expect(presenter.outcome == .copied)
        #expect(presenter.isPresented, "the sheet stays up to say it copied")
    }

    @Test
    func presentIdeaPrefillsTheDraft() {
        let presenter = make(FakeMailer())
        presenter.present(kind: .idea, text: "night mode")
        #expect(presenter.isPresented)
        #expect(presenter.draft.kind == .idea)
        #expect(presenter.draft.text == "night mode")
        #expect(presenter.draft.includesDetails)
        #expect(presenter.outcome == nil)
    }

    @Test
    func dismissResets() {
        let mailer = FakeMailer()
        mailer.canOpen = false
        let presenter = make(mailer)
        presenter.present(kind: .idea, text: "x")
        presenter.send()
        presenter.dismiss()
        #expect(!presenter.isPresented)
        #expect(presenter.draft == FeedbackDraft())
        #expect(presenter.outcome == nil)
    }
}

/// Draws the sheet with the frame's words. Set `OPEN_ISLAND_RENDER_SNAPSHOTS=1`
/// to write `feedback-mail.png` under `output/render/feedback-search/`.
@MainActor
struct FeedbackSheetRenderTests {
    @Test
    func theSheetRendersWithTheFramesWords() throws {
        let presenter = FeedbackPresenter(mailer: FakeMailer(), details: { fixedDetails })
        presenter.present(kind: .bug, text: "The island stays open after I press Later on the update ask.")

        let framed = FeedbackSheet(presenter: presenter)
            .frame(width: 520, height: 440)
            .background(Color(white: 0.11))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        #expect(!png.isEmpty)

        if ProcessInfo.processInfo.environment["OPEN_ISLAND_RENDER_SNAPSHOTS"] == "1" {
            let directory = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("output/render/feedback-search", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("feedback-mail.png"))
        }
    }
}
