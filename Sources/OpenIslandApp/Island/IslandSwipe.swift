import AppKit

/// Which way the fingers moved.
enum IslandSwipeDirection: Equatable, Sendable {
    case up, down, left, right
}

/// One scroll event, reduced to the numbers a swipe is told from. `dx` and
/// `dy` are in points, in the direction the fingers moved: `dy > 0` is
/// fingers up, `dx > 0` is fingers right, whatever the user's "natural
/// scrolling" setting says.
struct IslandScrollSample: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case began, changed, ended
        /// A plain wheel, which has no phases.
        case none
    }

    var dx: Double
    var dy: Double
    var phase: Phase
    /// The tail a trackpad keeps scrolling after the fingers lift.
    var isMomentum: Bool
    var timestamp: TimeInterval
    /// Whether the user's "natural scrolling" is on, which decides which way
    /// a list under the fingers travels. It does not change `dx` or `dy`.
    var isNaturalScrolling = true

    /// A wheel measures in lines. This many points make one line.
    static let pointsPerWheelLine = 12.0

    /// Turns the numbers of a scroll event into a sample. The caller reads
    /// them from the `NSEvent`, which never crosses to another thread.
    static func make(
        scrollingDeltaX: Double,
        scrollingDeltaY: Double,
        hasPreciseScrollingDeltas: Bool,
        isDirectionInvertedFromDevice: Bool,
        phase: NSEvent.Phase,
        momentumPhase: NSEvent.Phase,
        timestamp: TimeInterval
    ) -> IslandScrollSample {
        let scale = hasPreciseScrollingDeltas ? 1.0 : pointsPerWheelLine
        let dy = (isDirectionInvertedFromDevice ? -scrollingDeltaY : scrollingDeltaY) * scale
        let dx = (isDirectionInvertedFromDevice ? scrollingDeltaX : -scrollingDeltaX) * scale
        return IslandScrollSample(
            dx: dx,
            dy: dy,
            phase: Self.phase(of: phase),
            isMomentum: !momentumPhase.isEmpty,
            timestamp: timestamp,
            isNaturalScrolling: isDirectionInvertedFromDevice
        )
    }

    private static func phase(of phase: NSEvent.Phase) -> Phase {
        if phase.isEmpty { return .none }
        if phase.contains(.began) { return .began }
        if phase.contains(.ended) || phase.contains(.cancelled) { return .ended }
        return .changed
    }
}

/// Tells a swipe from the stream of scroll samples over the island. It
/// adds up one gesture, fires once when a clear direction passes the
/// threshold, and stays quiet until that gesture is over. One long
/// swipe is one swipe.
struct IslandSwipeRecognizer: Equatable, Sendable {
    /// How far the fingers travel along the main axis before it counts.
    static let threshold = 36.0
    /// The main axis must beat the other by this factor, which keeps a
    /// diagonal drag or a scroll that wobbles from counting.
    static let dominance = 2.0
    /// A wheel has no end event. A pause this long ends its gesture.
    static let wheelGap: TimeInterval = 0.25

    private var sumX = 0.0
    private var sumY = 0.0
    private var isActive = false
    private var lastTimestamp: TimeInterval?
    /// True from the moment a gesture fires until the next one starts.
    /// The local monitor can use it to swallow the rest of it.
    private(set) var hasFired = false
    /// True once the island acted on this gesture. The local monitor then
    /// swallows the rest of it. A list under the pointer then does not scroll
    /// as the island closes.
    private(set) var isConsumed = false

    mutating func reset() {
        self = IslandSwipeRecognizer()
    }

    mutating func markConsumed() {
        isConsumed = true
    }

    /// A sample that arrives with the pointer off the island. A gesture the
    /// island acted on stays consumed wherever the pointer goes, until the
    /// next gesture starts, and the answer says whether this sample still
    /// belongs to it. Anything else is forgotten.
    mutating func feedOffIsland(_ sample: IslandScrollSample) -> Bool {
        guard isConsumed else {
            reset()
            return false
        }
        _ = feed(sample)
        if isConsumed { return true }
        reset()
        return false
    }

    /// Whether a scroll gesture is under way at `now`: a sample came within
    /// the wheel gap. Hover-open waits while one is.
    func isInProgress(at now: TimeInterval) -> Bool {
        lastTimestamp.map { now - $0 <= Self.wheelGap } ?? false
    }

    mutating func feed(_ sample: IslandScrollSample) -> IslandSwipeDirection? {
        // The tail of a swipe is never a swipe.
        if sample.isMomentum { return nil }

        let gapped = lastTimestamp.map { sample.timestamp - $0 > Self.wheelGap } ?? true
        lastTimestamp = sample.timestamp
        switch sample.phase {
        case .began:
            start()
        case .none:
            if !isActive || gapped { start() }
        case .changed, .ended:
            // A gesture that began before the pointer got here is not ours.
            if !isActive { return nil }
        }

        sumX += sample.dx
        sumY += sample.dy
        if sample.phase == .ended { isActive = false }
        guard !hasFired else { return nil }

        let direction = Self.direction(sumX: sumX, sumY: sumY)
        if direction != nil { hasFired = true }
        return direction
    }

    private mutating func start() {
        sumX = 0
        sumY = 0
        isActive = true
        hasFired = false
        isConsumed = false
    }

    private static func direction(sumX: Double, sumY: Double) -> IslandSwipeDirection? {
        let ax = abs(sumX)
        let ay = abs(sumY)
        if ay >= threshold, ay >= ax * dominance { return sumY > 0 ? .up : .down }
        if ax >= threshold, ax >= ay * dominance { return sumX > 0 ? .right : .left }
        return nil
    }
}

/// The swipe is a setting, off until the user turns it on in Settings,
/// General (D46). The scroll monitors exist only while it is on, which keeps
/// a scroll anywhere on the Mac free while it is off.
enum IslandSwipeSetting {
    static let defaultsKey = "app.swipeGesturesEnabled"
}

/// Which way a list's content travels under the fingers, along the document
/// in reading order: toward its end shows what lies below the visible part.
enum IslandScrollTravel: Equatable, Sendable {
    case towardStart, towardEnd

    /// The way a list travels for a swipe, which depends on the user's
    /// natural scrolling setting: with it on, content follows the fingers.
    /// Sideways swipes travel nowhere a list scrolls.
    static func of(_ direction: IslandSwipeDirection, isNaturalScrolling: Bool) -> IslandScrollTravel? {
        switch direction {
        case .up: return isNaturalScrolling ? .towardEnd : .towardStart
        case .down: return isNaturalScrolling ? .towardStart : .towardEnd
        case .left, .right: return nil
        }
    }
}

/// Whether a scroll over the island belongs to something that scrolls.
enum IslandScrollContent {
    /// Past this much hidden content, a scroll view counts as scrollable.
    static let scrollableSlack: CGFloat = 1

    /// Walks up from the view under the pointer and answers true for a
    /// scroll view that can still travel `travel`: it hides more than the
    /// slack in that direction. A list at the end of its content does not
    /// count for a swipe that would push it further. Anything missing
    /// answers false.
    ///
    /// A hosting view may answer a hit test with itself instead of the
    /// scroll view inside it. With `windowPoint` the search also looks
    /// down from the view, through nested scroll views, for one under that
    /// point that can travel.
    @MainActor
    static func isScrollable(
        from view: NSView?,
        windowPoint: NSPoint? = nil,
        travel: IslandScrollTravel
    ) -> Bool {
        var current = view
        while let candidate = current {
            if let scrollView = candidate as? NSScrollView, canTravel(scrollView, travel) { return true }
            current = candidate.superview
        }
        guard let view, let windowPoint else { return false }
        return view.subviews.contains { holdsScrollableView($0, under: windowPoint, travel: travel) }
    }

    /// Whether a document seen through `visible` hides more than the slack
    /// in the direction of `travel`. Both rects are in the document's own
    /// coordinates. A flipped document starts at its lowest y, an unflipped
    /// one at its highest.
    static func canTravel(
        _ travel: IslandScrollTravel,
        visible: CGRect,
        document: CGRect,
        isFlipped: Bool
    ) -> Bool {
        let hiddenAtLowY = visible.minY - document.minY
        let hiddenAtHighY = document.maxY - visible.maxY
        let hiddenTowardStart = isFlipped ? hiddenAtLowY : hiddenAtHighY
        let hiddenTowardEnd = isFlipped ? hiddenAtHighY : hiddenAtLowY
        let hidden = travel == .towardEnd ? hiddenTowardEnd : hiddenTowardStart
        return hidden > scrollableSlack
    }

    @MainActor
    private static func canTravel(_ scrollView: NSScrollView, _ travel: IslandScrollTravel) -> Bool {
        guard let document = scrollView.documentView else { return false }
        return canTravel(
            travel,
            visible: scrollView.documentVisibleRect,
            document: document.bounds,
            isFlipped: document.isFlipped
        )
    }

    @MainActor
    private static func holdsScrollableView(
        _ view: NSView,
        under windowPoint: NSPoint,
        travel: IslandScrollTravel
    ) -> Bool {
        if let scrollView = view as? NSScrollView,
           scrollView.convert(scrollView.bounds, to: nil).contains(windowPoint),
           canTravel(scrollView, travel) {
            return true
        }
        // A scroll view that cannot travel may hold one that can.
        return view.subviews.contains { holdsScrollableView($0, under: windowPoint, travel: travel) }
    }
}
