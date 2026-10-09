import Foundation

/// What asked for a refresh. Each trigger has its own minimum spacing.
enum NotionRefreshTrigger: Sendable {
    /// The card appeared: the island opened to the Nook page.
    case opened
    /// The card's repeating timer while the island stays open.
    case timer
    /// The service's own poll while the island is closed.
    case background
    /// The user asked: a settings change, the refresh button, a new task.
    case manual
}

/// Decides whether a refresh may run now. Pure value type: the service owns
/// one and feeds it the clock, which keeps the policy testable.
struct NotionRefreshGate: Equatable, Sendable {
    /// Collapses bursts of card appearances into one request.
    static let openedSpacing: TimeInterval = 10
    static let timerSpacing: TimeInterval = 60
    static let backgroundSpacing: TimeInterval = 300
    static let backoffBase: TimeInterval = 5
    static let backoffCap: TimeInterval = 300
    static let defaultRateLimitWait: TimeInterval = 60

    private(set) var lastAttempt: Date?
    private(set) var consecutiveFailures = 0
    /// Backoff after failures. Automatic refreshes wait until this passes.
    private(set) var backoffUntil: Date?
    /// Set by a 429. Nothing refreshes until this passes, manual included.
    private(set) var rateLimitedUntil: Date?

    func shouldRun(_ trigger: NotionRefreshTrigger, now: Date) -> Bool {
        if let rateLimitedUntil, now < rateLimitedUntil { return false }
        if trigger == .manual { return true }
        if let backoffUntil, now < backoffUntil { return false }
        guard let lastAttempt else { return true }
        let elapsed = now.timeIntervalSince(lastAttempt)
        switch trigger {
        case .manual: return true
        case .opened: return elapsed >= Self.openedSpacing
        case .timer: return elapsed >= Self.timerSpacing
        case .background: return elapsed >= Self.backgroundSpacing
        }
    }

    mutating func recordAttempt(now: Date) {
        lastAttempt = now
    }

    mutating func recordSuccess() {
        consecutiveFailures = 0
        backoffUntil = nil
        rateLimitedUntil = nil
    }

    /// A 5xx or network failure: wait 5s, 10s, 20s and upward to the cap.
    mutating func recordFailure(now: Date) {
        consecutiveFailures += 1
        backoffUntil = now.addingTimeInterval(Self.backoff(afterFailures: consecutiveFailures))
    }

    /// A 429: wait as long as Notion asked.
    mutating func recordRateLimit(retryAfter: TimeInterval?, now: Date) {
        rateLimitedUntil = now.addingTimeInterval(max(retryAfter ?? Self.defaultRateLimitWait, 1))
    }

    func isRateLimited(now: Date) -> Bool {
        rateLimitedUntil.map { now < $0 } ?? false
    }

    /// Clears spacing and backoff for a new database or session. A rate
    /// limit belongs to the token, and survives unless `forgetRateLimit`.
    mutating func reset(forgetRateLimit: Bool = false) {
        let held = forgetRateLimit ? nil : rateLimitedUntil
        self = NotionRefreshGate()
        rateLimitedUntil = held
    }

    static func backoff(afterFailures count: Int) -> TimeInterval {
        guard count > 0 else { return 0 }
        let exponent = min(count - 1, 16)
        return min(backoffBase * pow(2, Double(exponent)), backoffCap)
    }
}
