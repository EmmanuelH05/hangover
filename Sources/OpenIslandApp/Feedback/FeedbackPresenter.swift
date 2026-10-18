import AppKit
import Foundation
import Observation

/// What opening a draft touches: the system's mail handling and the
/// clipboard. A test passes a fake so nothing real is opened or copied.
@MainActor protocol FeedbackMailing: AnyObject {
    func canOpenMail(_ url: URL) -> Bool
    func open(_ url: URL)
    func copy(_ text: String)
}

@MainActor final class NSWorkspaceFeedbackMailer: FeedbackMailing {
    func canOpenMail(_ url: URL) -> Bool {
        NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

@MainActor
@Observable
final class FeedbackPresenter {
    enum Outcome: Equatable {
        case opened
        case copied
    }

    var isPresented = false
    var draft = FeedbackDraft()
    var outcome: Outcome?

    @ObservationIgnored private let mailer: any FeedbackMailing
    @ObservationIgnored private let detailsProvider: () -> FeedbackDetails
    @ObservationIgnored let address: String
    @ObservationIgnored let appName: String

    init(
        mailer: any FeedbackMailing,
        details: @escaping () -> FeedbackDetails = { FeedbackDetails.current() },
        address: String = AppBrand.feedbackAddress,
        appName: String = AppBrand.name
    ) {
        self.mailer = mailer
        self.detailsProvider = details
        self.address = address
        self.appName = appName
    }

    /// The details the sheet shows under its switch.
    var details: FeedbackDetails { detailsProvider() }

    func present(kind: FeedbackKind = .bug, text: String = "") {
        draft = FeedbackDraft(kind: kind, text: text, includesDetails: true)
        outcome = nil
        isPresented = true
    }

    /// Opens the draft in the mail app when something handles mailto:,
    /// else copies the body for the user to paste (F10).
    func send() {
        let details = detailsProvider()
        if let url = draft.mailtoURL(to: address, appName: appName, details: details),
           mailer.canOpenMail(url) {
            mailer.open(url)
            outcome = .opened
            isPresented = false
        } else {
            mailer.copy(draft.body(details: details))
            outcome = .copied
        }
    }

    func dismiss() {
        isPresented = false
        draft = FeedbackDraft()
        outcome = nil
    }
}
