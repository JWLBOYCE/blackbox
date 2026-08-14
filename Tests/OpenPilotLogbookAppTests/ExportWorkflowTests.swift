import AppKit
import Foundation
import Testing
@testable import OpenPilotLogbook
import OpenPilotLogbookCore

@Suite("Export workflow boundaries", .serialized)
@MainActor
struct ExportWorkflowTests {
    @Test("Reveal forwards exactly the last exported CSV")
    func revealForwardsExactCSV() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let exports = fixture.root.appendingPathComponent("Exports", isDirectory: true)
        let csv = exports.appendingPathComponent("CAA_Logbook_Export_synthetic.csv")
        let html = exports.appendingPathComponent("CAA_Logbook_Printable_synthetic.html")

        fixture.store.revealLastExport()
        #expect(fixture.platformServices.revealRequests.isEmpty)

        fixture.store.lastExport = (csv: csv, html: html)
        fixture.store.revealLastExport()

        #expect(fixture.platformServices.revealRequests == [[csv]])
        #expect(fixture.store.statusMessage == "Requested Finder reveal for \(csv.path(percentEncoded: false))")
    }

    @Test("Synthetic export selection never bypasses the backup chooser")
    func syntheticExportSelectionIsExportOnly() throws {
        var selectionRequestCount = 0
        var syntheticExportFolder: URL?
        let fixture = try makeFixture {
            selectionRequestCount += 1
            return syntheticExportFolder
        }
        defer { fixture.cleanUp() }
        syntheticExportFolder = fixture.root.appendingPathComponent("Exports", isDirectory: true)

        fixture.store.chooseAndExportReports()
        #expect(selectionRequestCount == 1)
        #expect(fixture.platformServices.folderRequests.isEmpty)

        fixture.store.chooseAndCreateEncryptedBackup()
        #expect(selectionRequestCount == 1)
        #expect(fixture.platformServices.folderRequests == [
            FolderRequest(title: "Choose Backup Folder", prompt: "Back Up Here")
        ])
        #expect(fixture.store.selectedBackupFolder == nil)
    }

    private func makeFixture(
        syntheticExportFolderSelection: @escaping @MainActor () -> URL? = { nil }
    ) throws -> ExportStoreFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Blackbox-ExportWorkflowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let suiteName = "Blackbox.ExportWorkflowTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw ExportWorkflowFixtureError.couldNotCreateDefaults
        }
        let platformServices = ExportPlatformServicesSpy()
        let paths = LogbookPaths(
            backupFolder: root.appendingPathComponent("Backups", isDirectory: true),
            sourceLogTenDatabase: root.appendingPathComponent("Missing-LogTen.sqlite"),
            workingDatabase: root.appendingPathComponent("Blackbox.sqlite")
        )
        let store = LogbookStore(
            paths: paths,
            platformServices: platformServices,
            folderAccessStore: FolderAccessStore(
                defaults: defaults,
                keyPrefix: "Synthetic.exportWorkflow.folderBookmark",
                mode: .standard
            ),
            undoManager: UndoManager(),
            syntheticExportFolderSelection: syntheticExportFolderSelection
        )
        return ExportStoreFixture(
            store: store,
            platformServices: platformServices,
            root: root,
            defaults: defaults,
            suiteName: suiteName
        )
    }
}

private struct FolderRequest: Equatable {
    let title: String
    let prompt: String
}

@MainActor
private final class ExportPlatformServicesSpy: PlatformServices {
    private(set) var folderRequests: [FolderRequest] = []
    private(set) var revealRequests: [[URL]] = []

    func chooseFolder(title: String, prompt: String, completion: @escaping @MainActor (URL?) -> Void) {
        folderRequests.append(FolderRequest(title: title, prompt: prompt))
        completion(nil)
    }

    func reveal(_ urls: [URL]) {
        revealRequests.append(urls)
    }

    func open(_ url: URL) {}
}

@MainActor
private struct ExportStoreFixture {
    let store: LogbookStore
    let platformServices: ExportPlatformServicesSpy
    let root: URL
    let defaults: UserDefaults
    let suiteName: String

    func cleanUp() {
        store.sessionUndoManager.removeAllActions()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}

private enum ExportWorkflowFixtureError: Error {
    case couldNotCreateDefaults
}
