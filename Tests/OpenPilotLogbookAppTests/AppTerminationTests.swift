import AppKit
import Foundation
import Testing
@testable import OpenPilotLogbook
import OpenPilotLogbookCore

@Suite("Unsaved draft termination")
@MainActor
struct AppTerminationTests {
    @Test("Window close and application quit use explicit action labels")
    func closeAndQuitLabelsAreDistinct() {
        let closeAlert = AppDelegate.unsavedDraftAlert(for: .close)
        #expect(closeAlert.buttons.map(\.title) == [
            "Save Draft & Close",
            "Cancel",
            "Discard Changes & Close"
        ])
        #expect(closeAlert.buttons[2].hasDestructiveAction)

        let quitAlert = AppDelegate.unsavedDraftAlert(for: .quit)
        #expect(quitAlert.buttons.map(\.title) == [
            "Save Draft & Quit",
            "Cancel",
            "Discard Changes & Quit"
        ])
        #expect(quitAlert.buttons[2].hasDestructiveAction)
    }

    @Test("Save permits termination only after persistence succeeds")
    func saveMustSucceed() {
        var saveAttempts = 0
        let successfulReply = AppDelegate.terminationReply(for: .alertFirstButtonReturn) {
            saveAttempts += 1
            return true
        }
        #expect(successfulReply == .terminateNow)
        #expect(saveAttempts == 1)

        let failedReply = AppDelegate.terminationReply(for: .alertFirstButtonReturn) {
            saveAttempts += 1
            return false
        }
        #expect(failedReply == .terminateCancel)
        #expect(saveAttempts == 2)
    }

    @Test("Cancel preserves the running app without attempting a save")
    func cancelKeepsApplicationOpen() {
        var saveWasCalled = false
        let reply = AppDelegate.terminationReply(for: .alertSecondButtonReturn) {
            saveWasCalled = true
            return true
        }

        #expect(reply == .terminateCancel)
        #expect(!saveWasCalled)
    }

    @Test("Explicit discard permits termination without writing")
    func explicitDiscardPermitsTermination() {
        var saveWasCalled = false
        let reply = AppDelegate.terminationReply(for: .alertThirdButtonReturn) {
            saveWasCalled = true
            return true
        }

        #expect(reply == .terminateNow)
        #expect(!saveWasCalled)
    }

    @Test("Window-close discard restores a persisted draft without repository writes")
    func closeDiscardRestoresPersistedDraftWithoutWriting() throws {
        let fixture = try makeTerminationStore()
        defer { fixture.cleanUp() }

        let id = try fixture.store.repository.saveDraft(FlightEntry(
            date: Date(timeIntervalSinceReferenceDate: 800_100_000),
            departure: "EGLL",
            arrival: "EHAM",
            aircraftID: "G-CLOSE",
            totalMinutes: 75,
            remarks: "Persisted synthetic close fixture"
        ), origin: "app_test_fixture")
        fixture.store.refresh()
        fixture.store.selectFlightImmediately(id: id)

        let persisted = try #require(try fixture.store.repository.flight(id: id))
        let revisionsBefore = try fixture.store.repository.history()
        let suggestion = try #require(
            fixture.store.flightSuggestions.first { $0.field == .departureCoordinates && $0.isActionable }
        )
        fixture.store.acceptSuggestion(suggestion)
        fixture.store.draftFlight?.remarks = "Unsaved literal that must be discarded"
        fixture.store.draftDidChange()
        fixture.store.pendingSection = .history
        fixture.store.pendingSelectionID = nil
        fixture.store.pendingStartNew = true
        fixture.store.showDiscardConfirmation = true

        #expect(fixture.store.isDraftDirty)
        #expect(fixture.store.canUndoSessionAction)

        fixture.store.discardDraftForWindowClose()

        #expect(fixture.store.draftFlight == persisted)
        #expect(fixture.store.selectedFlightID == id)
        #expect(fixture.store.selectedRouteFlightIDs == Set([id]))
        #expect(!fixture.store.isDraftDirty)
        #expect(!fixture.store.canUndoSessionAction)
        #expect(fixture.store.pendingSection == nil)
        #expect(fixture.store.pendingSelectionID == nil)
        #expect(!fixture.store.pendingStartNew)
        #expect(!fixture.store.showDiscardConfirmation)
        #expect(try fixture.store.repository.flight(id: id) == persisted)
        #expect(try fixture.store.repository.history() == revisionsBefore)
    }

    @Test("Window-close discard clears a never-saved draft without creating a row")
    func closeDiscardClearsNeverSavedDraftWithoutWriting() throws {
        let fixture = try makeTerminationStore()
        defer { fixture.cleanUp() }

        let flightsBefore = try fixture.store.repository.flights()
        let revisionsBefore = try fixture.store.repository.history()
        fixture.store.startNewFlight()
        fixture.store.draftFlight?.departure = "EGLL"
        fixture.store.draftFlight?.arrival = "EHAM"
        fixture.store.draftDidChange()
        let suggestion = try #require(
            fixture.store.flightSuggestions.first { $0.field == .departureCoordinates && $0.isActionable }
        )
        fixture.store.acceptSuggestion(suggestion)

        #expect(fixture.store.isDraftDirty)
        #expect(fixture.store.canUndoSessionAction)

        fixture.store.discardDraftForWindowClose()

        #expect(fixture.store.draftFlight == nil)
        #expect(fixture.store.selectedFlightID == nil)
        #expect(fixture.store.selectedRouteFlightIDs.isEmpty)
        #expect(fixture.store.flightSuggestions.isEmpty)
        #expect(fixture.store.selectedSuggestionIDs.isEmpty)
        #expect(!fixture.store.isDraftDirty)
        #expect(!fixture.store.canUndoSessionAction)
        #expect(try fixture.store.repository.flights() == flightsBefore)
        #expect(try fixture.store.repository.history() == revisionsBefore)
    }

    private func makeTerminationStore() throws -> TerminationStoreFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Blackbox-TerminationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let suiteName = "Blackbox.TerminationTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TerminationFixtureError.couldNotCreateDefaults
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
                keyPrefix: "Synthetic.termination.folderBookmark",
                mode: .standard
            ),
            undoManager: UndoManager()
        )
        return TerminationStoreFixture(store: store, root: root, defaults: defaults, suiteName: suiteName)
    }
}

@MainActor
private struct TerminationStoreFixture {
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

private enum TerminationFixtureError: Error {
    case couldNotCreateDefaults
}
