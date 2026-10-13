import Foundation
import OpenIslandCore

/// Where a task source's token lives. The app uses a private file; tests use
/// an in-memory store.
protocol NookTodoTokenStoring: Sendable {
    func read() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

/// Why the token file could not be used. Carries a reason and a system error
/// number, never the token and never a path.
struct NookTodoTokenFileError: Error, Equatable, Sendable {
    enum Reason: String, Equatable, Sendable {
        /// A link sits where the file should be. A link could point anywhere.
        case symbolicLink
        /// A folder or another kind of item sits where the file should be.
        case notRegularFile
        /// The mode lets group or others in. The file is no longer private.
        case readableByOthers
        /// The file belongs to another account on this Mac.
        case otherOwner
        /// The folder is a link, is not a folder, or belongs to another
        /// account.
        case unsafeFolder
        /// The file could not be opened or read, holds bytes that are not
        /// text, or holds more than one word.
        case unreadable
        /// The folder or the file could not be written.
        case cannotSave
        /// The file could not be removed.
        case cannotRemove
        /// The Keychain item an older build left could not be removed.
        case oldItemRemains
    }

    let reason: Reason
    /// The `errno` behind the failure, when there was one.
    let code: Int32?

    init(_ reason: Reason, code: Int32? = nil) {
        self.reason = reason
        self.code = code
    }

    /// The sentence that says what happened, in the user's language.
    var messageKey: String { "nook.todo.token.problem.\(reason.rawValue)" }
}

/// One small file per task source under the app's state folder:
/// `Secrets/<bundle identifier>.todo-notion.token`. The folder is mode 0700
/// and the file is mode 0600. Only the user's own account can read it.
///
/// This replaces the Keychain, which asks again after every update for an
/// app that is not signed with a paid certificate. The folder is opened once
/// without following a link, and everything after that goes through that
/// open folder, which keeps a link swapped in later from redirecting a read,
/// a write or a delete. The file is written atomically (a sibling file, then
/// a rename) and its mode is set again after every write. A read refuses a
/// link, anything that is not a regular file, a file or folder that belongs
/// to another account, and a file that group or others can reach.
struct NookTodoTokenFile: NookTodoTokenStoring {
    static let folderName = "Secrets"
    static let notionKind = "todo-notion"
    static let tickTickKind = "todo-ticktick"
    static let fileExtension = "token"
    static let fallbackBundleID = "app.openisland.dev"
    static let folderMode: mode_t = 0o700
    static let fileMode: mode_t = 0o600
    /// A token is a few dozen characters. Anything bigger is not one. A save
    /// and a read hold to the same limit.
    static let maxBytes = 8 * 1024

    /// One save or delete at a time, which keeps one from sweeping away the
    /// temporary file of the other.
    private static let lock = NSLock()

    /// The Notion integration token.
    static var notion: NookTodoTokenFile { NookTodoTokenFile(kind: notionKind) }

    /// The TickTick API token.
    static var tickTick: NookTodoTokenFile { NookTodoTokenFile(kind: tickTickKind) }

    let folder: URL
    let fileName: String
    /// The account that must own the file. The folder must always belong to
    /// the account running the app. A test passes another one here to stand
    /// in for a file that belongs to someone else.
    let userID: uid_t

    /// Pass a folder in tests. The file name keeps the bundle identifier in
    /// it, which keeps a dev copy and the installed app apart: they share
    /// one state folder.
    init(folder: URL, fileName: String, userID: uid_t = geteuid()) {
        self.folder = folder
        self.fileName = fileName
        self.userID = userID
    }

    init(kind: String, bundleID: String? = nil) {
        self.init(
            folder: OpenIslandStateDirectory.url.appendingPathComponent(Self.folderName, isDirectory: true),
            fileName: Self.fileName(kind: kind, bundleID: bundleID ?? Bundle.main.bundleIdentifier)
        )
    }

    /// `<bundle identifier>.<kind>.token`, with anything that could change
    /// the path turned into an underscore.
    static func fileName(kind: String, bundleID: String?) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        let id = (bundleID ?? fallbackBundleID).map { allowed.contains($0) ? $0 : "_" }
        return "\(String(id)).\(kind).\(fileExtension)"
    }

    var fileURL: URL { folder.appendingPathComponent(fileName) }

    /// What a save accepts: one unbroken run of characters, not empty and
    /// not past the size limit. It is what a read hands back as it is.
    static func isStorable(_ token: String) -> Bool {
        !token.isEmpty
            && token.utf8.count <= maxBytes
            && !token.contains(where: { $0.isWhitespace || $0.isNewline })
    }

    // MARK: Read

    /// Nil when there is no file or it holds only blank space. Surrounding
    /// blank space is dropped, because a stray newline in a header value
    /// leaves the header unset. Throws for a file that is not safe to trust.
    func read() throws -> String? {
        guard let folderDescriptor = try openFolder() else { return nil }
        defer { close(folderDescriptor) }

        let descriptor = openat(folderDescriptor, fileName, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            let code = errno
            switch code {
            case ENOENT: return nil
            case ELOOP: throw NookTodoTokenFileError(.symbolicLink, code: code)
            default: throw NookTodoTokenFileError(.unreadable, code: code)
            }
        }
        defer { close(descriptor) }

        // The checks run on the open descriptor, which keeps a swap between
        // the check and the read from mattering.
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw NookTodoTokenFileError(.unreadable, code: errno) }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw NookTodoTokenFileError(.notRegularFile) }
        guard info.st_uid == userID else { throw NookTodoTokenFileError(.otherOwner) }
        guard info.st_mode & (S_IRWXG | S_IRWXO) == 0 else { throw NookTodoTokenFileError(.readableByOthers) }
        guard info.st_size <= Self.maxBytes else { throw NookTodoTokenFileError(.unreadable) }

        let data = try Self.readAll(from: descriptor)
        guard let text = String(data: data, encoding: .utf8) else { throw NookTodoTokenFileError(.unreadable) }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }
        guard !token.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw NookTodoTokenFileError(.unreadable)
        }
        return token
    }

    private static func readAll(from descriptor: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw NookTodoTokenFileError(.unreadable, code: errno)
            }
            if count == 0 { return data }
            data.append(contentsOf: buffer[0..<count])
            guard data.count <= maxBytes else { throw NookTodoTokenFileError(.unreadable) }
        }
    }

    // MARK: Save

    func save(_ token: String) throws {
        guard Self.isStorable(token) else { throw NookTodoTokenFileError(.cannotSave) }
        try Self.lock.withLock {
            let folderDescriptor = try openFolderForSave()
            defer { close(folderDescriptor) }
            removeLeftovers(in: folderDescriptor)

            let temporaryName = ".\(fileName).\(UUID().uuidString).tmp"
            // Created private from the first byte. The token is never in a
            // file others could open.
            let descriptor = openat(
                folderDescriptor, temporaryName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, Self.fileMode
            )
            guard descriptor >= 0 else { throw NookTodoTokenFileError(.cannotSave, code: errno) }
            var isInPlace = false
            defer {
                close(descriptor)
                if !isInPlace { unlinkat(folderDescriptor, temporaryName, 0) }
            }

            // Whatever the umask said, the file is private before a byte goes in.
            guard fchmod(descriptor, Self.fileMode) == 0 else { throw NookTodoTokenFileError(.cannotSave, code: errno) }
            try Self.writeAll(Data(token.utf8), to: descriptor)
            guard fsync(descriptor) == 0 else { throw NookTodoTokenFileError(.cannotSave, code: errno) }
            guard renameat(folderDescriptor, temporaryName, folderDescriptor, fileName) == 0 else {
                throw NookTodoTokenFileError(.cannotSave, code: errno)
            }
            isInPlace = true
            // Set again after the write, on the file that is now in place.
            guard fchmod(descriptor, Self.fileMode) == 0 else { throw NookTodoTokenFileError(.cannotSave, code: errno) }
        }
    }

    /// Opens the folder, making it first when it is missing, and sets its
    /// mode every time. When the folder is new it is kept out of backups.
    private func openFolderForSave() throws -> Int32 {
        var isNew = false
        var opened = try openFolder()
        if opened == nil {
            do {
                try FileManager.default.createDirectory(
                    at: folder.deletingLastPathComponent(), withIntermediateDirectories: true
                )
            } catch {
                throw NookTodoTokenFileError(.cannotSave)
            }
            if mkdir(folder.path, Self.folderMode) == 0 {
                isNew = true
            } else if errno != EEXIST {
                throw NookTodoTokenFileError(.cannotSave, code: errno)
            }
            // Something may have appeared in the folder's place between the
            // two calls. Whatever is there is looked at, not trusted.
            opened = try openFolder()
        }
        guard let descriptor = opened else { throw NookTodoTokenFileError(.cannotSave) }
        guard fchmod(descriptor, Self.folderMode) == 0 else {
            let code = errno
            close(descriptor)
            throw NookTodoTokenFileError(.cannotSave, code: code)
        }
        if isNew { excludeFromBackups() }
        return descriptor
    }

    /// The token is for this Mac. A failure here leaves the folder private
    /// all the same, which is why it does not stop a save.
    private func excludeFromBackups() {
        var url = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(descriptor, raw.baseAddress.map { $0 + offset }, raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw NookTodoTokenFileError(.cannotSave, code: errno)
                }
                offset += written
            }
        }
    }

    // MARK: Delete

    /// A missing file counts as deleted. A link is removed, not followed.
    func delete() throws {
        try Self.lock.withLock {
            guard let folderDescriptor = try openFolder() else { return }
            defer { close(folderDescriptor) }
            removeLeftovers(in: folderDescriptor)
            guard unlinkat(folderDescriptor, fileName, 0) == 0 || errno == ENOENT else {
                throw NookTodoTokenFileError(.cannotRemove, code: errno)
            }
        }
    }

    // MARK: Folder

    /// Opens the folder itself and never through a link. Nil when there is
    /// no folder yet. A link, a file in its place or another account's
    /// folder is refused.
    private func openFolder() throws -> Int32? {
        let descriptor = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            let code = errno
            switch code {
            case ENOENT: return nil
            case ELOOP, ENOTDIR: throw NookTodoTokenFileError(.unsafeFolder, code: code)
            default: throw NookTodoTokenFileError(.unreadable, code: code)
            }
        }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            let code = errno
            close(descriptor)
            throw NookTodoTokenFileError(.unreadable, code: code)
        }
        guard info.st_uid == geteuid() else {
            close(descriptor)
            throw NookTodoTokenFileError(.unsafeFolder)
        }
        return descriptor
    }

    /// A save that was killed between creating its file and renaming it
    /// leaves `.<name>.<id>.tmp` behind, holding the token. Every save and
    /// delete sweeps those away. A failure to remove one is not fatal: the
    /// file is private, and the next sweep tries again.
    private func removeLeftovers(in folderDescriptor: Int32) {
        let prefix = ".\(fileName)."
        let copy = dup(folderDescriptor)
        guard copy >= 0, let directory = fdopendir(copy) else {
            if copy >= 0 { close(copy) }
            return
        }
        defer { closedir(directory) }
        var found: [String] = []
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            if name.hasPrefix(prefix), name.hasSuffix(".tmp") { found.append(name) }
        }
        for name in found { unlinkat(folderDescriptor, name, 0) }
    }
}
