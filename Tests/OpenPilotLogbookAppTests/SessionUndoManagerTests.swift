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
        let fixture = try makeStore(injectUndoManager: false)
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

    @Test("PICUS allocation Undo and Redo preserve the complete day and night split")
    func picusAllocationUndoAndRedo() throws {
        let fixture = try makeStore()
        defer { fixture.cleanUp() }

        fixture.store.startNewFlight()
        fixture.store.draftFlight?.departure = "EGLL"
        fixture.store.draftFlight?.arrival = "EGKK"
        fixture.store.draftFlight?.pilotFunction = "PICUS"
        fixture.store.draftFlight?.totalMinutes = 60
        fixture.store.draftFlight?.nightMinutes = 0
        fixture.store.draftDidChange()

        let suggestion = try #require(
            fixture.store.flightSuggestions.first { $0.field == .picusMinutes && $0.isActionable }
        )
        fixture.store.acceptSuggestion(suggestion)
        #expect(fixture.store.draftFlight?.picusMinutes == 60)
        #expect(fixture.store.draftFlight?.picusDayMinutes == 60)
        #expect(fixture.store.draftFlight?.picusNightMinutes == 0)

        fixture.store.undoLastSessionAction()
        #expect(fixture.store.draftFlight?.picusMinutes == 0)
        #expect(fixture.store.draftFlight?.picusDayMinutes == 0)
        #expect(fixture.store.draftFlight?.picusNightMinutes == 0)

        fixture.store.redoLastSessionAction()
        #expect(fixture.store.draftFlight?.picusMinutes == 60)
        #expect(fixture.store.draftFlight?.picusDayMinutes == 60)
        #expect(fixture.store.draftFlight?.picusNightMinutes == 0)
    }

    @Test("A newer native text edit is undone before an older session action")
    func commandRoutingPreservesNewerNativeUndo() throws {
        let fixture = try makeStore()
        defer { fixture.cleanUp() }

        fixture.store.startNewFlight()
        fixture.store.draftFlight?.departure = "EGLL"
        fixture.store.draftDidChange()
        let suggestion = try #require(
            fixture.store.flightSuggestions.first { $0.field == .departureCoordinates }
        )
        fixture.store.acceptSuggestion(suggestion)

        let nativeManager = UndoManager()
        nativeManager.groupsByEvent = false
        let router = UndoCommandRouter(
            store: fixture.store,
            activeResponderUndoManager: { nativeManager }
        )
        let probe = NativeUndoProbe()
        nativeManager.beginUndoGrouping()
        nativeManager.registerUndo(withTarget: probe) { target in
            target.undoCount += 1
        }
        nativeManager.setActionName("Native Text Edit")
        nativeManager.endUndoGrouping()

        router.undo()
        #expect(probe.undoCount == 1)
        #expect(fixture.store.draftFlight?.departureLatitude != nil)

        router.undo()
        #expect(fixture.store.statusMessage == "Undid Departure coordinates suggestion")
        #expect(fixture.store.draftFlight?.departureLatitude == nil)
    }

    @Test("Redo restores an older session action before the later native edit")
    func commandRoutingPreservesChronologicalRedo() throws {
        let fixture = try makeStore()
        defer { fixture.cleanUp() }

        fixture.store.startNewFlight()
        fixture.store.draftFlight?.departure = "EGLL"
        fixture.store.draftDidChange()
        let suggestion = try #require(
            fixture.store.flightSuggestions.first { $0.field == .departureCoordinates }
        )
        let nativeManager = UndoManager()
        nativeManager.groupsByEvent = false
        let probe = NativeUndoProbe()
        fixture.store.acceptSuggestion(suggestion)
        nativeManager.beginUndoGrouping()
        nativeManager.registerUndo(withTarget: probe) { target in
            target.undoCount += 1
            nativeManager.registerUndo(withTarget: target) { redoTarget in
                redoTarget.redoCount += 1
            }
        }
        nativeManager.setActionName("Native Text Edit")
        nativeManager.endUndoGrouping()
        let router = UndoCommandRouter(
            store: fixture.store,
            activeResponderUndoManager: { nativeManager }
        )
        nativeManager.undo()
        fixture.store.undoLastSessionAction()
        #expect(nativeManager.canRedo)
        #expect(fixture.store.canRedoSessionAction)

        router.redo()
        #expect(fixture.store.statusMessage == "Redid Departure coordinates suggestion")
        #expect(probe.redoCount == 0)

        router.redo()
        #expect(probe.redoCount == 1)
    }

    @Test("A new native branch invalidates an abandoned session Redo")
    func newNativeBranchInvalidatesSessionRedo() throws {
        let fixture = try makeStore()
        defer { fixture.cleanUp() }

        fixture.store.startNewFlight()
        fixture.store.draftFlight?.departure = "EGLL"
        fixture.store.draftDidChange()
        let suggestion = try #require(
            fixture.store.flightSuggestions.first { $0.field == .departureCoordinates }
        )
        fixture.store.acceptSuggestion(suggestion)
        fixture.store.undoLastSessionAction()
        #expect(fixture.store.canRedoSessionAction)

        let nativeManager = UndoManager()
        nativeManager.groupsByEvent = false
        let probe = NativeUndoProbe()
        nativeManager.beginUndoGrouping()
        nativeManager.registerUndo(withTarget: probe) { target in
            target.undoCount += 1
        }
        nativeManager.endUndoGrouping()
        let router = UndoCommandRouter(
            store: fixture.store,
            activeResponderUndoManager: { nativeManager }
        )

        router.redo()

        #expect(fixture.store.draftFlight?.departureLatitude == nil)
        #expect(!fixture.store.canRedoSessionAction)
        #expect(probe.undoCount == 0)
    }

    @Test("A Blackbox operation clears stale Undo from an unfocused text editor")
    func operationClearsUnfocusedTextEditorUndo() throws {
        let fixture = try makeStore(injectUndoManager: false)
        defer { fixture.cleanUp() }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        let unfocusedTextView = IsolatedUndoTextView(frame: NSRect(x: 0, y: 0, width: 120, height: 80))
        container.addSubview(unfocusedTextView)
        window.contentView = container
        let delegate = AppDelegate()
        delegate.bind(window: window, store: fixture.store)

        let staleProbe = NativeUndoProbe()
        let staleManager = unfocusedTextView.isolatedUndoManager
        staleManager.beginUndoGrouping()
        staleManager.registerUndo(withTarget: staleProbe) { target in
            target.undoCount += 1
        }
        staleManager.endUndoGrouping()
        #expect(staleManager.canUndo)

        fixture.store.startNewFlight()
        fixture.store.draftFlight?.departure = "EGLL"
        fixture.store.draftDidChange()
        let suggestion = try #require(
            fixture.store.flightSuggestions.first { $0.field == .departureCoordinates }
        )
        fixture.store.acceptSuggestion(suggestion)

        #expect(!staleManager.canUndo)
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

    @Test("A programmatic same-row selection never raises unsaved navigation")
    func sameRowSelectionEchoIsIgnored() throws {
        let fixture = try makeStore()
        defer { fixture.cleanUp() }

        let id = try fixture.store.repository.saveDraft(FlightEntry(
            date: Date(timeIntervalSinceReferenceDate: 800_000_000),
            departure: "EGLL",
            arrival: "EHAM",
            aircraftID: "G-SELECT",
            totalMinutes: 60
        ), origin: "app_test_fixture")
        fixture.store.refresh()
        fixture.store.selectFlightImmediately(id: id)
        fixture.store.draftFlight?.remarks = "Locally edited after the selection callback was queued"
        fixture.store.draftDidChange()

        fixture.store.selectFlight(id: id)

        #expect(fixture.store.selectedFlightID == id)
        #expect(fixture.store.draftFlight?.remarks == "Locally edited after the selection callback was queued")
        #expect(fixture.store.isDraftDirty)
        #expect(!fixture.store.showDiscardConfirmation)
        #expect(fixture.store.pendingSelectionID == nil)
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

    @Test("Trash ends stale field editing before selecting the fallback flight")
    func trashUndoCannotMutateFallbackFlight() throws {
        let fixture = try makeStore(injectUndoManager: false)
        defer { fixture.cleanUp() }

        let fallbackID = try fixture.store.repository.saveDraft(FlightEntry(
            date: Date(timeIntervalSinceReferenceDate: 799_999_000),
            departure: "EHAM",
            arrival: "EDDF",
            aircraftID: "G-FALLBACK",
            totalMinutes: 45
        ), origin: "app_test_fixture")
        let trashedID = try fixture.store.repository.saveDraft(FlightEntry(
            date: Date(timeIntervalSinceReferenceDate: 800_000_000),
            departure: "EGLL",
            arrival: "EHAM",
            aircraftID: "G-TRASH",
            totalMinutes: 60
        ), origin: "app_test_fixture")
        fixture.store.refresh()
        fixture.store.selectFlightImmediately(id: trashedID)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let fieldEditor = IsolatedUndoTextView(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        window.contentView = fieldEditor
        let delegate = AppDelegate()
        delegate.bind(window: window, store: fixture.store)
        _ = window.makeFirstResponder(fieldEditor)

        let staleProbe = NativeUndoProbe()
        fieldEditor.isolatedUndoManager.beginUndoGrouping()
        fieldEditor.isolatedUndoManager.registerUndo(withTarget: staleProbe) { target in
            target.undoCount += 1
        }
        fieldEditor.isolatedUndoManager.endUndoGrouping()
        #expect(fieldEditor.isolatedUndoManager.canUndo)

        fixture.store.deleteSelectedFlight()

        #expect(!fieldEditor.isolatedUndoManager.canUndo)
        #expect(fixture.store.selectedFlightID == fallbackID)
        #expect(fixture.store.draftFlight?.departure == "EHAM")
        #expect(fixture.store.draftFlight?.arrival == "EDDF")
        #expect(!fixture.store.isDraftDirty)

        UndoCommandRouter(
            store: fixture.store,
            activeResponderUndoManager: { fieldEditor.isolatedUndoManager }
        ).undo()

        #expect(staleProbe.undoCount == 0)
        #expect(try fixture.store.repository.flight(id: trashedID)?.recordState == .draft)
        #expect(fixture.store.selectedFlightID == trashedID)
        #expect(fixture.store.statusMessage == "Restored draft from Trash")

        UndoCommandRouter(
            store: fixture.store,
            activeResponderUndoManager: { fieldEditor.isolatedUndoManager }
        ).redo()

        #expect(try fixture.store.repository.flight(id: trashedID)?.recordState == .trashed)
        #expect(fixture.store.selectedFlightID == fallbackID)
        #expect(fixture.store.draftFlight?.departure == "EHAM")
        #expect(fixture.store.draftFlight?.arrival == "EDDF")
        #expect(!fixture.store.isDraftDirty)

        UndoCommandRouter(
            store: fixture.store,
            activeResponderUndoManager: { fieldEditor.isolatedUndoManager }
        ).undo()

        #expect(try fixture.store.repository.flight(id: trashedID)?.recordState == .draft)
        #expect(fixture.store.selectedFlightID == trashedID)
        #expect(staleProbe.undoCount == 0)
    }

    @Test("Trash blocks a focus-loss edit without clearing its native Undo")
    func trashRechecksBufferedEditBeforeMutation() throws {
        let fixture = try makeStore(injectUndoManager: false)
        defer { fixture.cleanUp() }

        let id = try fixture.store.repository.saveDraft(FlightEntry(
            date: Date(timeIntervalSinceReferenceDate: 800_000_000),
            departure: "EGLL",
            arrival: "EHAM",
            aircraftID: "G-BUFFER",
            totalMinutes: 60,
            remarks: "Persisted"
        ), origin: "app_test_fixture")
        fixture.store.refresh()
        fixture.store.selectFlightImmediately(id: id)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let fieldEditor = CommitOnResignUndoTextView(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        fieldEditor.onResign = {
            fixture.store.draftFlight?.remarks = "Buffered until focus loss"
        }
        window.contentView = fieldEditor
        let delegate = AppDelegate()
        delegate.bind(window: window, store: fixture.store)
        #expect(window.makeFirstResponder(fieldEditor))

        let nativeProbe = NativeUndoProbe()
        fieldEditor.isolatedUndoManager.beginUndoGrouping()
        fieldEditor.isolatedUndoManager.registerUndo(withTarget: nativeProbe) { target in
            target.undoCount += 1
        }
        fieldEditor.isolatedUndoManager.endUndoGrouping()
        #expect(fieldEditor.isolatedUndoManager.canUndo)
        #expect(!fixture.store.isDraftDirty)

        fixture.store.deleteSelectedFlight()

        #expect(try fixture.store.repository.flight(id: id)?.recordState == .draft)
        #expect(fixture.store.draftFlight?.remarks == "Buffered until focus loss")
        #expect(fixture.store.isDraftDirty)
        #expect(fieldEditor.isolatedUndoManager.canUndo)
        #expect(fixture.store.statusMessage == "Save or discard unsaved changes before moving this draft to Trash")
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

    private func makeStore(injectUndoManager: Bool = true) throws -> StoreFixture {
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
            undoManager: injectUndoManager ? UndoManager() : nil
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

@MainActor
private final class NativeUndoProbe: NSObject {
    var undoCount = 0
    var redoCount = 0
}

@MainActor
private class IsolatedUndoTextView: NSTextView {
    let isolatedUndoManager: UndoManager = {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }()

    override var undoManager: UndoManager? { isolatedUndoManager }
}

@MainActor
private final class CommitOnResignUndoTextView: IsolatedUndoTextView {
    var onResign: (() -> Void)?

    override func resignFirstResponder() -> Bool {
        onResign?()
        return super.resignFirstResponder()
    }
}
