import Foundation
import os

/// Where Claude Code keeps the settings files whose ask rules count for a
/// session. Every location is handed in, which lets a test point all of
/// them at a temporary folder.
public struct ClaudeSettingsLocations: Equatable, Sendable {
    /// The user's settings file.
    public var userSettings: URL
    /// The folder of `managed-settings.json` and its `managed-settings.d`
    /// folder. Nil reads no managed settings.
    public var managedDirectory: URL?
    /// Walking up from a session's folder stops below this one.
    public var home: URL

    public init(userSettings: URL, managedDirectory: URL?, home: URL) {
        self.userSettings = userSettings
        self.managedDirectory = managedDirectory
        self.home = home
    }

    /// The files on this Mac: the user's settings in the Claude config
    /// folder, and the system folder for managed settings.
    public static func live() -> ClaudeSettingsLocations {
        ClaudeSettingsLocations(
            userSettings: ClaudeConfigDirectory.resolved().appendingPathComponent("settings.json"),
            managedDirectory: URL(fileURLWithPath: "/Library/Application Support/ClaudeCode", isDirectory: true),
            home: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    /// How many folders up from the session's folder are looked at.
    static let deepestWalk = 40

    /// `.claude/settings.json` and `.claude/settings.local.json` of the
    /// session's folder and of each folder above it, up to and not
    /// counting the home folder or the root. Claude Code reads the shared
    /// file from the folder the session started in and keeps the local one
    /// at the top of the repository. A hook only reports the folder the
    /// session is in now, which can be below both.
    public func projectSettings(forWorkingDirectory workingDirectory: String) -> [URL] {
        guard workingDirectory.hasPrefix("/") else { return [] }
        let homePath = home.standardizedFileURL.path
        var folder = URL(fileURLWithPath: workingDirectory, isDirectory: true).standardizedFileURL
        var files: [URL] = []

        for _ in 0..<Self.deepestWalk {
            // The root is never a project.
            if folder.path == "/" { break }
            let claude = folder.appendingPathComponent(".claude", isDirectory: true)
            files.append(claude.appendingPathComponent("settings.json"))
            files.append(claude.appendingPathComponent("settings.local.json"))

            // A session in the home folder itself has nothing above it to read.
            if folder.path == homePath { break }
            let parent = folder.deletingLastPathComponent().standardizedFileURL
            if parent.path == folder.path || parent.path == homePath || parent.path == "/" { break }
            folder = parent
        }
        return files
    }
}

/// What reading one settings file for its ask rules gave.
public enum ClaudeAskRuleFileOutcome: Equatable, Sendable {
    case rules([ClaudeAskRule])
    case missing
    case unreadable(String)
    case invalid(String)

    var rules: [ClaudeAskRule] {
        if case let .rules(rules) = self { return rules }
        return []
    }
}

/// Reads `permissions.ask` out of Claude Code's settings files and answers
/// whether one of those rules matches a tool call. It only reads. A file
/// that is missing, unreadable or not JSON gives no rules.
///
/// It cannot see rules handed to Claude Code on its command line with
/// `--settings`, rules from a device policy or the claude.ai console, or
/// the files of a session on another machine.
public final class ClaudeAskRuleSource: @unchecked Sendable {
    /// The real files of this Mac.
    public static let live = ClaudeAskRuleSource(locations: { .live() })

    /// A settings file is a few kilobytes. One past this size is not read.
    static let largestFile = 4 * 1024 * 1024

    private static let logger = Logger(subsystem: "app.openisland", category: "claudeAskRules")

    private struct CachedFile {
        /// The file a link points to, or the file itself.
        var target: String
        var modified: Date?
        var size: Int
        var outcome: ClaudeAskRuleFileOutcome
    }

    private let locations: @Sendable () -> ClaudeSettingsLocations
    private let lock = NSLock()
    private var cache: [String: CachedFile] = [:]

    /// `locations` is asked on every lookup, because the Claude config
    /// folder can be changed while the app runs.
    public init(locations: @escaping @Sendable () -> ClaudeSettingsLocations) {
        self.locations = locations
    }

    /// The first ask rule that matches this hook's tool call, or nil. Only
    /// Claude Code on this Mac is looked at: the agents that share its hook
    /// format keep their own settings, and a remote session's files are on
    /// another machine.
    public func matchingRule(for payload: ClaudeHookPayload) -> ClaudeAskRule? {
        guard payload.resolvedAgentTool == .claudeCode, payload.remote != true,
              let toolName = payload.toolName, !toolName.isEmpty else {
            return nil
        }
        return matchingRule(toolName: toolName, toolInput: payload.toolInput, workingDirectory: payload.cwd)
    }

    public func matchingRule(
        toolName: String,
        toolInput: ClaudeHookJSONValue?,
        workingDirectory: String
    ) -> ClaudeAskRule? {
        ClaudeAskRuleMatcher.firstMatch(
            in: rules(forWorkingDirectory: workingDirectory),
            toolName: toolName,
            toolInput: toolInput
        )
    }

    /// Every ask rule that counts for a session in `workingDirectory`.
    public func rules(forWorkingDirectory workingDirectory: String) -> [ClaudeAskRule] {
        let files = settingsFiles(forWorkingDirectory: workingDirectory)
        var rules: [ClaudeAskRule] = []
        var missing = 0
        for file in files {
            let outcome = self.outcome(for: file)
            if outcome == .missing { missing += 1 }
            rules.append(contentsOf: outcome.rules)
        }
        Self.logger.debug(
            "Read \(rules.count, privacy: .public) Claude ask rules from \(files.count - missing, privacy: .public) settings files, \(missing, privacy: .public) not there"
        )
        return rules
    }

    /// The files looked at for a session in `workingDirectory`, each once:
    /// managed settings, the user's settings, then the project's.
    func settingsFiles(forWorkingDirectory workingDirectory: String) -> [URL] {
        let locations = locations()
        var files: [URL] = []
        if let managed = locations.managedDirectory {
            files.append(managed.appendingPathComponent("managed-settings.json"))
            let dropIns = managed.appendingPathComponent("managed-settings.d", isDirectory: true)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: dropIns.path)) ?? []
            files.append(contentsOf: names.filter { $0.hasSuffix(".json") }.sorted().map { dropIns.appendingPathComponent($0) })
        }
        files.append(locations.userSettings)
        files.append(contentsOf: locations.projectSettings(forWorkingDirectory: workingDirectory))

        var seen: Set<String> = []
        return files.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// Reads a file again only when its date or size changed. A settings
    /// file is often a link into a dotfiles folder: the date and the size
    /// are those of the file the link points to, never of the link.
    func outcome(for file: URL) -> ClaudeAskRuleFileOutcome {
        let path = file.standardizedFileURL.path
        let target = file.resolvingSymlinksInPath().path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: target) else {
            lock.withLock { cache[path] = nil }
            return .missing
        }
        let modified = attributes[.modificationDate] as? Date
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0

        if let cached = lock.withLock({ cache[path] }),
           cached.target == target, cached.modified == modified, cached.size == size {
            return cached.outcome
        }

        let isRegularFile = (attributes[.type] as? FileAttributeType) == .typeRegular
        let outcome = isRegularFile
            ? Self.read(URL(fileURLWithPath: target), size: size)
            : ClaudeAskRuleFileOutcome.unreadable("it is not a file")
        switch outcome {
        case let .unreadable(reason):
            Self.logger.error(
                "Could not read \(Self.shortName(file), privacy: .public) for its ask rules: \(reason, privacy: .public). Path: \(path, privacy: .private)"
            )
        case let .invalid(reason):
            Self.logger.error(
                "\(Self.shortName(file), privacy: .public) is not usable JSON, its ask rules are skipped: \(reason, privacy: .public). Path: \(path, privacy: .private)"
            )
        case .rules, .missing:
            break
        }
        lock.withLock { cache[path] = CachedFile(target: target, modified: modified, size: size, outcome: outcome) }
        return outcome
    }

    /// The ask rules of one settings file.
    static func read(_ file: URL, size: Int? = nil) -> ClaudeAskRuleFileOutcome {
        if let size, size > largestFile { return .unreadable("the file is too large") }
        // Never more than the limit plus one byte is read, whatever the
        // size on record says: a file can grow between the two.
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            data = try handle.read(upToCount: largestFile + 1) ?? Data()
        } catch {
            return FileManager.default.fileExists(atPath: file.path) ? .unreadable(error.localizedDescription) : .missing
        }
        guard data.count <= largestFile else { return .unreadable("the file is too large") }

        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            return .invalid(error.localizedDescription)
        }
        guard let settings = json as? [String: Any] else { return .invalid("the top level is not an object") }
        guard let permissions = settings["permissions"] as? [String: Any],
              let entries = permissions["ask"] as? [Any] else {
            return .rules([])
        }
        return .rules(entries.compactMap { ($0 as? String).flatMap { ClaudeAskRule($0) } })
    }

    /// The last two parts of a path, which name the file without the
    /// folders above it.
    static func shortName(_ file: URL) -> String {
        file.pathComponents.suffix(2).joined(separator: "/")
    }
}
