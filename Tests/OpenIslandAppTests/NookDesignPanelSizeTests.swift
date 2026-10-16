import CoreGraphics
import Foundation
import Testing
@testable import OpenIslandApp

private typealias Samples = NookDesignSamples

/// The size a reference's floating panel is left at is kept on the
/// reference and handed to the panel the next time it opens.
@MainActor
@Suite struct NookDesignPanelSizeTests {
    private func referencesFolder(_ fixture: NookDesignFixture) -> URL {
        fixture.folder.appendingPathComponent("References", isDirectory: true)
    }

    private func reopened(_ fixture: NookDesignFixture) async -> NookDesignReferenceStore {
        let store = NookDesignReferenceStore(folder: referencesFolder(fixture))
        await store.load()
        return store
    }

    private func indexJSON(_ fixture: NookDesignFixture) throws -> [String: Any] {
        let data = try Data(contentsOf: NookDesignReferenceFiles.indexURL(in: referencesFolder(fixture)))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Remembering

    @Test func aPanelTheUserResizedIsRememberedOnItsReference() async throws {
        let fixture = try await NookDesignFixture("panel-size")
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        await fixture.kit.openReference(item.id)?.value

        fixture.presenter.userResizes(item.id, to: CGSize(width: 520, height: 300))

        #expect(fixture.kit.references.item(item.id)?.panelSize == CGSize(width: 520, height: 300))
    }

    @Test func aPanelOpensAtTheSizeItsReferenceRemembers() async throws {
        let fixture = try await NookDesignFixture("panel-reopen")
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        await fixture.kit.openReference(item.id)?.value
        fixture.presenter.userResizes(item.id, to: CGSize(width: 640, height: 420))
        fixture.presenter.userCloses(item.id)

        await fixture.kit.openReference(item.id)?.value

        // The first time it had nothing, and the second it has what the user left.
        #expect(fixture.presenter.rememberedSizes == [nil, CGSize(width: 640, height: 420)])
    }

    @Test func aPictureNeverResizedHandsNoSizeToItsPanel() async throws {
        let fixture = try await NookDesignFixture("panel-never")
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()

        await fixture.kit.openReference(item.id)?.value
        fixture.presenter.userCloses(item.id)
        await fixture.kit.openReference(item.id)?.value

        #expect(fixture.presenter.rememberedSizes == [nil, nil])
        #expect(fixture.kit.references.item(item.id)?.panelSize == nil)
    }

    @Test func eachPictureKeepsItsOwnSize() async throws {
        let fixture = try await NookDesignFixture("panel-each")
        defer { fixture.cleanUp() }
        let first = try await fixture.addPicture(named: "first.png")
        let second = try await fixture.addPicture(named: "second.png")
        await fixture.kit.openReference(first.id)?.value
        await fixture.kit.openReference(second.id)?.value

        fixture.presenter.userResizes(first.id, to: CGSize(width: 300, height: 700))
        fixture.presenter.userResizes(second.id, to: CGSize(width: 900, height: 260))

        #expect(fixture.kit.references.item(first.id)?.panelSize == CGSize(width: 300, height: 700))
        #expect(fixture.kit.references.item(second.id)?.panelSize == CGSize(width: 900, height: 260))
    }

    @Test func theSizeIsKeptInWholePoints() async throws {
        let fixture = try await NookDesignFixture("panel-whole")
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()

        fixture.kit.references.rememberPanelSize(item.id, CGSize(width: 520.4, height: 300.6))

        #expect(fixture.kit.references.item(item.id)?.panelSize == CGSize(width: 520, height: 301))
    }

    @Test func aSizeThatCannotBeASizeIsNotKept() async throws {
        let fixture = try await NookDesignFixture("panel-bad")
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        let nan = CGFloat.nan
        let endless = CGFloat.infinity

        for bad in [
            CGSize.zero, CGSize(width: -300, height: 200), CGSize(width: 300, height: 0),
            CGSize(width: nan, height: 200), CGSize(width: 300, height: endless), CGSize(width: 1e9, height: 200),
        ] {
            fixture.kit.references.rememberPanelSize(item.id, bad)
        }

        #expect(fixture.kit.references.item(item.id)?.panelSize == nil)
        #expect(!fixture.kit.references.hasPendingWrites)
    }

    @Test func aSizeThatIsAlreadyKeptWritesNothingAgain() async throws {
        let fixture = try await NookDesignFixture("panel-same")
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        fixture.kit.references.rememberPanelSize(item.id, CGSize(width: 520, height: 300))
        await fixture.kit.references.flush()

        fixture.kit.references.rememberPanelSize(item.id, CGSize(width: 520, height: 300))

        #expect(!fixture.kit.references.hasPendingWrites)
    }

    @Test func aPictureThatIsNotOnTheShelfKeepsNothing() async throws {
        let fixture = try await NookDesignFixture("panel-gone")
        defer { fixture.cleanUp() }

        fixture.kit.references.rememberPanelSize(UUID(), CGSize(width: 520, height: 300))

        #expect(fixture.kit.references.items.isEmpty)
        #expect(!fixture.kit.references.hasPendingWrites)
    }

    // MARK: On disk

    @Test func theSizeSurvivesALaunch() async throws {
        let fixture = try await NookDesignFixture("panel-launch")
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        let other = try await fixture.addPicture(named: "other.png")
        fixture.kit.references.rememberPanelSize(item.id, CGSize(width: 520, height: 300))
        await fixture.kit.references.flush()

        let next = await reopened(fixture)

        #expect(next.item(item.id)?.panelSize == CGSize(width: 520, height: 300))
        #expect(next.item(other.id)?.panelSize == nil)
        #expect(next.loadProblem == nil)
    }

    @Test func aListSavedBeforeTheSizeWasKeptLoadsWithNothingWrong() async throws {
        let fixture = try await NookDesignFixture("panel-old")
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        await fixture.kit.references.flush()
        // What an older build wrote: the same list with neither key.
        let old = try indexJSON(fixture)
        let entries = try #require(old["items"] as? [[String: Any]])
        #expect(entries.allSatisfy { $0["panelWidth"] == nil && $0["panelHeight"] == nil })

        let next = await reopened(fixture)

        #expect(next.item(item.id) != nil)
        #expect(next.item(item.id)?.panelSize == nil)
        #expect(next.loadProblem == nil)
    }

    @Test func aListThatNeverHadASizeIsWrittenWithoutTheKeys() async throws {
        let fixture = try await NookDesignFixture("panel-keys")
        defer { fixture.cleanUp() }
        try await fixture.addPicture()
        await fixture.kit.references.flush()

        let entries = try #require(try indexJSON(fixture)["items"] as? [[String: Any]])

        #expect(entries.count == 1)
        #expect(entries[0]["panelWidth"] == nil)
        #expect(entries[0]["panelHeight"] == nil)
    }

    @Test func theFileVersionStaysSoAnOlderCopyOfTheAppStillReadsIt() async throws {
        let fixture = try await NookDesignFixture("panel-version")
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        fixture.kit.references.rememberPanelSize(item.id, CGSize(width: 520, height: 300))
        await fixture.kit.references.flush()

        let json = try indexJSON(fixture)
        #expect(json["version"] as? Int == 1)
        #expect(NookDesignReferenceFiles.currentVersion == 1)
        let entries = try #require(json["items"] as? [[String: Any]])
        #expect(entries[0]["panelWidth"] as? Int == 520)
        #expect(entries[0]["panelHeight"] as? Int == 300)

        // An older copy decodes by the keys it knows and ignores the rest.
        struct OlderItem: Decodable {
            var id: UUID
            var fileName: String
            var pixelWidth: Int
        }
        struct OlderList: Decodable {
            var version: Int
            var items: [OlderItem]
        }
        let data = try Data(contentsOf: NookDesignReferenceFiles.indexURL(in: referencesFolder(fixture)))
        let older = try JSONDecoder().decode(OlderList.self, from: data)
        #expect(older.items.map(\.id) == [item.id])
    }

    @Test func aSizeWrittenAsTheWrongKindOfValueKeepsThePictureAndLosesOnlyTheSize() async throws {
        let fixture = try await NookDesignFixture("panel-wrong")
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        await fixture.kit.references.flush()
        var json = try indexJSON(fixture)
        var entries = try #require(json["items"] as? [[String: Any]])
        entries[0]["panelWidth"] = "wide"
        entries[0]["panelHeight"] = NSNull()
        json["items"] = entries
        try JSONSerialization.data(withJSONObject: json)
            .write(to: NookDesignReferenceFiles.indexURL(in: referencesFolder(fixture)))

        let next = await reopened(fixture)

        #expect(next.item(item.id) != nil)
        #expect(next.item(item.id)?.panelSize == nil)
        // The value that did not read is counted, as any other is.
        #expect(next.loadProblem == .partlyRead(skipped: 1))
    }

    @Test func aShelfFromANewerVersionKeepsItsListAndSaysNothing() async throws {
        let fixture = try await NookDesignFixture("panel-newer")
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        await fixture.kit.references.flush()
        var refused = 0
        fixture.kit.references.onRefused = { _ in refused += 1 }
        // Another copy of the app, a newer one, saves its own list.
        let index = NookDesignReferenceFiles.indexURL(in: referencesFolder(fixture))
        try Data(#"{ "version": 9, "items": [], "somethingNew": true }"#.utf8).write(to: index)
        let newer = try Data(contentsOf: index)

        fixture.kit.references.rememberPanelSize(item.id, CGSize(width: 520, height: 300))
        await fixture.kit.references.flush()

        #expect(fixture.kit.references.lock == .newerVersion(9))
        #expect(refused == 0)
        #expect(try Data(contentsOf: index) == newer)
    }

    @Test func aListAnotherCopyChangedIsReadBeforeTheSizeIsAdded() async throws {
        let fixture = try await NookDesignFixture("panel-other-copy")
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        await fixture.kit.references.flush()
        // The other copy renames the picture and saves.
        let other = NookDesignReferenceStore(folder: referencesFolder(fixture))
        await other.load()
        other.rename(item.id, to: "Renamed elsewhere")
        await other.flush()

        fixture.kit.references.rememberPanelSize(item.id, CGSize(width: 520, height: 300))
        await fixture.kit.references.flush()

        let next = await reopened(fixture)
        #expect(next.item(item.id)?.name == "Renamed elsewhere")
        #expect(next.item(item.id)?.panelSize == CGSize(width: 520, height: 300))
    }

    // MARK: Opening on a smaller screen

    @Test func aStoredSizeLargerThanASmallerScreenIsClampedToIt() async throws {
        let fixture = try await NookDesignFixture("panel-screen")
        defer { fixture.cleanUp() }
        let item = try await fixture.addPicture()
        fixture.kit.references.rememberPanelSize(item.id, CGSize(width: 1800, height: 1100))
        let stored = try #require(fixture.kit.references.item(item.id))

        let smaller = CGSize(width: 1000, height: 700)
        let size = NookDesignPanelRules.openingSize(
            remembered: stored.panelSize, pictureAspect: stored.aspectRatio, available: smaller
        )

        #expect(size == smaller)
        // On the screen it was made for, it opens as it was left.
        let larger = CGSize(width: 2400, height: 1400)
        let same = NookDesignPanelRules.openingSize(
            remembered: stored.panelSize, pictureAspect: stored.aspectRatio, available: larger
        )
        #expect(same == CGSize(width: 1800, height: 1100))
    }
}
