import Foundation
import Testing
@testable import OpenIslandApp

/// Where the now playing adapter is looked for. The packaged app keeps the
/// perl script in `Contents/Resources`, the dev bundle in
/// `Contents/Helpers`, and both keep the framework in `Contents/Frameworks`.
struct MediaRemoteAdapterLocatorTests {
    /// A made-up app bundle in the temporary folder, removed by the caller.
    private func makeBundle(scriptFolders: [String], withFramework: Bool = true) throws -> URL {
        let bundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapter-locator-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Sample.app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        for folder in scriptFolders {
            let directory = contents.appendingPathComponent(folder, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("#!/usr/bin/perl\n".utf8).write(to: directory.appendingPathComponent("mediaremote-adapter.pl"))
        }
        if withFramework {
            let framework = contents.appendingPathComponent("Frameworks/MediaRemoteAdapter.framework", isDirectory: true)
            try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
            try Data("binary".utf8).write(to: framework.appendingPathComponent("MediaRemoteAdapter"))
        }
        return bundle
    }

    private func remove(_ bundle: URL) {
        try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent())
    }

    private func scriptFolder(_ paths: MediaRemoteAdapterLocator.Paths?) -> String? {
        paths?.script.deletingLastPathComponent().lastPathComponent
    }

    @Test func thePackagedAppFindsItsScriptInResources() throws {
        let bundle = try makeBundle(scriptFolders: ["Resources"])
        defer { remove(bundle) }

        let found = MediaRemoteAdapterLocator(bundleURL: bundle, environment: [:]).resolve()

        let expected: String = "Resources"
        #expect(scriptFolder(found) == expected)
        #expect(found?.framework.path.hasPrefix(bundle.path) == true)
    }

    @Test func theDevBundleStillFindsItsScriptInHelpers() throws {
        let bundle = try makeBundle(scriptFolders: ["Helpers"])
        defer { remove(bundle) }

        let found = MediaRemoteAdapterLocator(bundleURL: bundle, environment: [:]).resolve()

        let expected: String = "Helpers"
        #expect(scriptFolder(found) == expected)
    }

    @Test func resourcesWinsWhenBothFoldersHoldTheScript() throws {
        let bundle = try makeBundle(scriptFolders: ["Helpers", "Resources"])
        defer { remove(bundle) }

        let found = MediaRemoteAdapterLocator(bundleURL: bundle, environment: [:]).resolve()

        let expected: String = "Resources"
        #expect(scriptFolder(found) == expected)
    }

    @Test func aBundleWithNoFrameworkIsNotUsed() throws {
        let bundle = try makeBundle(scriptFolders: ["Resources"], withFramework: false)
        defer { remove(bundle) }

        // The repo's own build of the adapter may answer instead, which is
        // why this only says the half-made bundle did not.
        let found = MediaRemoteAdapterLocator(bundleURL: bundle, environment: [:]).resolve()

        #expect(found?.script.path.hasPrefix(bundle.path) != true)
    }

    @Test func theOverrideFolderComesFirst() throws {
        let bundle = try makeBundle(scriptFolders: ["Resources"])
        defer { remove(bundle) }
        let override = bundle.deletingLastPathComponent().appendingPathComponent("override", isDirectory: true)
        let framework = override.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: framework.appendingPathComponent("MediaRemoteAdapter"))
        try Data("#!/usr/bin/perl\n".utf8).write(to: override.appendingPathComponent("mediaremote-adapter.pl"))

        let found = MediaRemoteAdapterLocator(
            bundleURL: bundle,
            environment: ["OPEN_ISLAND_MEDIAREMOTE_DIR": override.path]
        ).resolve()

        let expected: String = "override"
        #expect(scriptFolder(found) == expected)
    }
}
