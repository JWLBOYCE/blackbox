import AppKit
import Foundation
import Testing
@testable import OpenPilotLogbook
import OpenPilotLogbookCore

@Suite("Durable session Undo", .serialized)
@MainActor
struct SessionUndoManagerTests {
    @Test("The primary window exposes the operation Undo manager to AppKit")
    func primaryWindowReturnsSessionUndoManager() throws {
        let fixture = try makeStore()
        defer { fixture.cleanUp() }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let delegate = AppDelegate()
        delegate.bind(window: window, store: fixture.store)

        #expect(delegate.windowWillReturnUndoManager(window) === fixture.store.sessionUndoManager)
        #expect(window.undoManager === fixture.store.sessionUndoManager)
    }

    @Test("Selected suggestion acceptance supports Undo and Redo without a window")
    func suggestionBatchUndoAndRedoWithoutWindow() throws {
        let fixture = try makeStore()
        defer { fixture.cleanUp() }

        fixture.store.startNewFlight()
        fixture.store.draftFlight?.departure = "EGLL"
        fixture.store.draftFlight?.arrival = "EHAM"
        fixture.store.draftDidChange()

        let coordinateSuggestions = fixture.store.flightSuggestions.filter {
            $0.field == .departureCoordinates || $0.field == .arrivalCoordinates
        }
        #expect(coordinateSuggestions.count == 2)
        fixture.store.selectedSuggestionIDs = Set(coordinateSuggestions.map(\.id))

        fixture.store.acceptSelectedSuggestions()
        #expect(fixture.store.draftFlight?.departureLatitude != nil)
        #expect(fixture.store.draftFlight?.arrivalLatitude != nil)
        #expect(fixture.store.canUndoSessionAction)
        #expect(fixture.store.undoCommandTitle == "Undo Accept Selected Suggestions")

        fixture.store.draftFlight?.route = "LAM UL9 KONAN"
        fixture.store.draftDidChange()

        fixture.store.undoLastSessionAction()
        #expect(fixture.store.draftFlight?.departureLatitude == nil)
        #expect(fixture.store.draftFlight?.departureLongitude == nil)
        #expect(fixture.store.draftFlight?.arrivalLatitude == nil)
        #expect(fixture.store.draftFlight?.arrivalLongitude == nil)
        #expect(fixture.store.draftFlight?.route == "LAM UL9 KONAN")
        #expect(fixture.store.statusMessage == "Undid accepted suggestions")
        #expect(fixture.store.canRedoSessionAction)
        #expect(fixture.store.redoCommandTitle == "Redo Accept Selected Suggestions")

        fixture.store.redoLastSessionAction()
        #expect(fixture.store.draftFlight?.departureLatitude != nil)
        #expect(fixture.store.draftFlight?.arrivalLatitude != nil)
        #expect(fixture.store.statusMessage == "Redid accepted suggestions")
        #expect(fixture.store.canUndoSessionAction)
    }

    @Test("Suggestion Undo cannot alter a different draft")
    func suggestionUndoIsScopedToOriginalDraft() throws {
        let fixture = try makeStore()
        defer { fixture.cleanUp() }

        fixture.store.startNewFlight()
        fixture.store.draftFlight?.departure = "EGLL"
        fixture.store.draftFlight?.arrival = "EHAM"
        fixture.store.draftDidChange()
        let coordinateSuggestions = fixture.store.flightSuggestions.filter {
            $0.field == .departureCoordinates || $0.field == .arrivalCoordinates
        }
        fixture.store.selectedSuggestionIDs = Set(coordinateSuggestions.map(\.id))
        fixture.store.acceptSelectedSuggestions()
        #expect(fixture.store.canUndoSessionAction)

        #expect(fixture.store.saveDraft())
        fixture.store.startNewFlight()
        fixture.store.draftFlight?.departure = "EDDF"
        fixture.store.draftFlight?.arrival = "LIRF"
        fixture.store.draftDidChange()
        #expect(!fixture.store.canUndoSessionAction)

        fixture.store.undoLastSessionAction()
        #expect(fixture.store.draftFlight?.departure == "EDDF")
        #expect(fixture.store.draftFlight?.arrival == "LIRF")
        #expect(fixture.store.draftFlight?.departureLatitude == nil)
        #expect(fixture.store.draftFlight?.arrivalLatitude == nil)
    }

    @Test("Suggestion Undo refuses an affected field changed afterward")
    func suggestionUndoRefusesChangedAffectedField() throws {
        let fixture = try makeStore()
        defer { fixture.cleanUp() }

        fixture.store.startNewFlight()
        fixture.store.draftFlight?.departure = "EGLL"
        fixture.store.draftDidChange()
        let suggestion = try #require(fixture.store.flightSuggestions.first { $0.field == .departureCoordinates })
        fixture.store.acceptSuggestion(suggestion)
        fixture.store.draftFlight?.departureLatitude = 48.0
        fixture.store.draftDidChange()

        fixture.store.undoLastSessionAction()

        #expect(fixture.store.draftFlight?.departureLatitude == 48.0)
        #expect(fixture.store.statusMessage.contains("an affected field changed afterward"))
    }

    @Test("Trash supports durable Undo and Redo without a window")
    func trashUndoAndRedoWithoutWindow() throws {
        let fixture = try makeStore()
        defer { fixture.cleanUp() }

        let id = try fixture.store.repository.saveDraft(FlightEntry(
            date: Date(timeIntervalSinceReferenceDate: 800_000_000),
            departure: "EGLL",
            arrival: "EHAM",
            aircraftID: "G-SYNTH",
            totalMinutes: 60,
            remarks: "Synthetic session Undo fixture"
        ), origin: "app_test_fixture")
        fixture.store.refresh()
        fixture.store.selectFlightImmediately(id: id)

        fixture.store.deleteSelectedFlight()
        #expect(try fixture.store.repository.flight(id: id)?.recordState == .trashed)
        #expect(fixture.store.canUndoSessionAction)
        #expect(fixture.store.undoCommandTitle == "Undo Move Draft to Trash")

        fixture.store.undoLastSessionAction()
        #expect(try fixture.store.repository.flight(id: id)?.recordState == .draft)
        #expect(fixture.store.selectedFlightID == id)
        #expect(fixture.store.statusMessage == "Restored draft from Trash")
        #expect(fixture.store.canRedoSessionAction)

        fixture.store.redoLastSessionAction()
        #expect(try fixture.store.repository.flight(id: id)?.recordState == .trashed)
        #expect(fixture.store.statusMessage == "Moved draft to Trash")
        #expect(fixture.store.canUndoSessionAction)
    }

    @Test("Trash Undo never displaces another dirty draft")
    func trashUndoRefusesDirtyEditor() throws {
        let fixture = try makeStore()
        defer { fixture.cleanUp() }

        let trashedID = try fixture.store.repository.saveDraft(FlightEntry(
            date: Date(timeIntervalSinceReferenceDate: 800_000_000),
            departure: "EGLL",
            arrival: "EHAM",
            aircraftID: "G-SYNTH",
            totalMinutes: 60
        ), origin: "app_test_fixture")
        _ = try fixture.store.repository.saveDraft(FlightEntry(
            date: Date(timeIntervalSinceReferenceDate: 800_001_000),
            departure: "EDDF",
            arrival: "LIRF",
            aircraftID: "G-SYNTH2",
            totalMinutes: 75
        ), origin: "app_test_fixture")
        fixture.store.refresh()
        fixture.store.selectFlightImmediately(id: trashedID)
        fixture.store.deleteSelectedFlight()
        #expect(try fixture.store.repository.flight(id: trashedID)?.recordState == .trashed)

        fixture.store.draftFlight?.remarks = "Unsaved fact on the clean fallback selection"
        fixture.store.draftDidChange()
        let dirtyID = fixture.store.draftFlight?.id
        fixture.store.undoLastSessionAction()

        #expect(try fixture.store.repository.flight(id: trashedID)?.recordState == .trashed)
        #expect(fixture.store.draftFlight?.id == dirtyID)
        #expect(fixture.store.draftFlight?.remarks == "Unsaved fact on the clean fallback selection")
        #expect(fixture.store.statusMessage == "Could not restore from Undo because another draft has unsaved changes")
    }

    private func makeStore() throws -> StoreFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Blackbox-AppTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let suiteName = "Blackbox.AppTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw FixtureError.couldNotCreateDefaults
        }
        let paths = LogbookPaths(
            backupFolder: root.appendingPathComponent("Backups", isDirectory: true),
            sourceLogTenDatabase: root.appendingPathComponent("Missing-LogTen.sqlite"),
            workingDatabase: root.appendingPathComponent("Blackbox.sqlite")
        )
        let store = LogbookStore(
            paths: paths,
            folderAccessStore: FolderAccessStore(
                defaults: defaults,
                keyPrefix: "Synthetic.folderBookmark",
                mode: .standard
            ),
            undoManager: UndoManager()
        )
        return StoreFixture(store: store, root: root, defaults: defaults, suiteName: suiteName)
    }
}

@MainActor
private struct StoreFixture {
    let store: LogbookStore
    let root: URL
    let defaults: UserDefaults
    let suiteName: String

    func cleanUp() {
        store.sessionUndoManager.removeAllActions()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}

private enum FixtureError: Error {
    case couldNotCreateDefaults
}
