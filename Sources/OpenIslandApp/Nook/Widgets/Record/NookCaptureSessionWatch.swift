import AVFoundation
import Foundation

/// Tells when a capture session stops without being asked: a runtime error
/// (a device unplugged, AirPods disconnected) or an interruption (another app
/// took the device). Nothing in an `AVCaptureSession` says so on its own, and
/// until now the voice track and the face cam went quiet without a word.
///
/// It reports the first problem only. A session that failed once usually
/// fails again, and one notice is enough.
final class NookCaptureSessionWatch: @unchecked Sendable {
    enum Problem: Equatable, Sendable {
        case runtimeError
        case interrupted
    }

    private let lock = NSLock()
    private var observers: [NSObjectProtocol] = []
    private var hasReported = false
    private let onProblem: @Sendable (Problem) -> Void

    /// `onProblem` runs on whatever thread posted the notification.
    init(session: AVCaptureSession, onProblem: @escaping @Sendable (Problem) -> Void) {
        self.onProblem = onProblem
        let center = NotificationCenter.default
        let runtime = center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] _ in
            self?.report(.runtimeError)
        }
        let interrupted = center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            self?.report(.interrupted)
        }
        observers = [runtime, interrupted]
    }

    deinit {
        stop()
    }

    /// Stops listening. Safe to call twice.
    func stop() {
        let held = lock.withLock { () -> [NSObjectProtocol] in
            defer { observers = [] }
            return observers
        }
        for observer in held { NotificationCenter.default.removeObserver(observer) }
    }

    private func report(_ problem: Problem) {
        let isFirst = lock.withLock { () -> Bool in
            defer { hasReported = true }
            return !hasReported
        }
        if isFirst { onProblem(problem) }
    }
}
