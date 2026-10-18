import Foundation

/// One thing a release changed, in the words the What's new card uses.
struct WhatsNewItem: Equatable, Sendable, Decodable {
    var title: String
    /// The sub line under the title. Nil when the title says it all.
    var detail: String?
    /// The symbol on the item's plate. Nil draws the plate with the
    /// card's own mark.
    var symbol: String?
}

/// Every user-facing change of one version.
struct WhatsNewRelease: Equatable, Sendable, Decodable {
    var version: String
    var items: [WhatsNewItem]
}

/// The words of the What's new card for every version, newest first. The
/// app reads them from `WhatsNew.json` in its bundle, which
/// `scripts/whats-new.ts` writes from `design/update-flow/WHATS-NEW.md`:
/// the Markdown file is where the words are written, the JSON is what
/// ships. A version with nothing to show has no entry (D82).
struct WhatsNewCatalog: Equatable, Sendable, Decodable {
    var releases: [WhatsNewRelease]

    static let empty = WhatsNewCatalog(releases: [])
    static let resourceName = "WhatsNew"

    /// How many of a version's items the card shows; the eyebrow's count
    /// says how many there are in all.
    static let shownPerRelease = 3
    /// How many rows the card holds across every skipped version, which
    /// keeps the open island on the screen after a long gap. "See all"
    /// has the rest.
    static let maxShown = 6

    /// The catalog in the bundle. An unreadable file is an empty catalog,
    /// never a crash: the card is a courtesy.
    static func bundled(_ bundle: Bundle = .appResources) -> WhatsNewCatalog {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let catalog = try? parse(data) else { return .empty }
        return catalog
    }

    static func parse(_ data: Data) throws -> WhatsNewCatalog {
        try JSONDecoder().decode(WhatsNewCatalog.self, from: data)
    }

    /// The versions the user skipped: after `lastSeen` and up to `current`,
    /// newest first, only the ones with something to show.
    func releases(after lastSeen: String, upTo current: String) -> [WhatsNewRelease] {
        releases
            .filter { release in
                !release.items.isEmpty
                    && AppVersion.compare(release.version, lastSeen) == .orderedDescending
                    && AppVersion.compare(release.version, current) != .orderedDescending
            }
            .sorted { AppVersion.compare($0.version, $1.version) == .orderedDescending }
    }
}

/// What the What's new card has to show after a relaunch.
struct WhatsNewPending: Equatable, Sendable {
    /// The skipped versions, newest first.
    var releases: [WhatsNewRelease]

    /// The newest version, the one the eyebrow names.
    var version: String { releases.first?.version ?? "" }

    /// Every item across the skipped versions.
    var totalCount: Int { releases.reduce(0) { $0 + $1.items.count } }

    /// The rows the card draws: the first few of each version, newest
    /// version first, and never more than the card can hold.
    var shown: [WhatsNewItem] {
        Array(releases.flatMap { $0.items.prefix(WhatsNewCatalog.shownPerRelease) }.prefix(WhatsNewCatalog.maxShown))
    }

    /// True when the card leaves something out, which is what "See all"
    /// is for.
    var hasMore: Bool { totalCount > shown.count }
}

/// Dotted version strings compared number by number, which puts 1.0.14
/// after 1.0.9. A missing part counts as zero: 1.0 is 1.0.0.
enum AppVersion {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parts(lhs)
        let right = parts(rhs)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
    }
}
