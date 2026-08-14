import Foundation
import Testing
@testable import OpenPilotLogbook
import OpenPilotLogbookCore

@Suite("UI-test launch root safety")
struct UITestLaunchConfigurationTests {
    @Test("Debug launches disable live LogTen discovery")
    func debugLaunchesDisableLiveLogTenDiscovery() {
#if DEBUG
        #expect(!UITestLaunchConfiguration.allowsLiveLogTenDiscoveryForCurrentLaunch())
#endif
    }

    @Test("Synthetic folder selection is fixed beneath the marked UI root")
    func syntheticFolderSelectionIsConfinedToUIRoot() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("Blackbox-XCUITest-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let baseEnvironment = [
            "BLACKBOX_DATA_ROOT": root.path,
            "BLACKBOX_SYNTHETIC_FIXTURE": "deterministic"
        ]
        _ = UITestLaunchConfiguration.pathsForCurrentLaunch(
            arguments: ["Blackbox", "--ui-testing"],
            environment: baseEnvironment,
            fileManager: fileManager
        )

        #expect(UITestLaunchConfiguration.syntheticFolderSelectionForCurrentLaunch(
            arguments: ["Blackbox", "--ui-testing"],
            environment: baseEnvironment,
            fileManager: fileManager
        ) == nil)

        var exportEnvironment = baseEnvironment
        exportEnvironment["BLACKBOX_UI_TEST_FOLDER_SELECTION"] = "exports"
        let selection = UITestLaunchConfiguration.syntheticFolderSelectionForCurrentLaunch(
            arguments: ["Blackbox", "--ui-testing"],
            environment: exportEnvironment,
            fileManager: fileManager
        )
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        #expect(selection == canonicalRoot.appendingPathComponent("Exports", isDirectory: true))
        #expect(selection?.deletingLastPathComponent() == canonicalRoot)

        let argumentSelection = UITestLaunchConfiguration.syntheticFolderSelectionForCurrentLaunch(
            arguments: ["Blackbox", "--ui-testing", "--ui-testing-folder-selection=exports"],
            environment: baseEnvironment,
            fileManager: fileManager
        )
        #expect(argumentSelection == selection)
    }

    @Test("UI test windows are fitted inside the visible screen")
    func testWindowFramesAreFittedAndCentered() {
        let visible = NSRect(x: 0, y: 0, width: 1_024, height: 768)
        let oversized = UITestLaunchConfiguration.fittedTestWindowFrame(
            requestedFrame: NSRect(x: 0, y: 0, width: 1_440, height: 980),
            visibleFrame: visible
        )
        #expect(oversized == NSRect(x: 12, y: 12, width: 1_000, height: 744))

        let regular = UITestLaunchConfiguration.fittedTestWindowFrame(
            requestedFrame: NSRect(x: 0, y: 0, width: 900, height: 700),
            visibleFrame: visible
        )
        #expect(regular.size == NSSize(width: 900, height: 700))
        #expect(regular.midX == visible.midX)
        #expect(regular.midY == visible.midY)
    }

    @Test("Canonical runner temporary direct child is accepted")
    func canonicalRunnerTemporaryDirectChildIsAccepted() throws {
        let syntheticHome = URL(fileURLWithPath: "/Users/Synthetic-Blackbox-Test", isDirectory: true)
        let systemTemporaryDirectory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        let runnerTemporaryDirectory = syntheticHome
            .appendingPathComponent("Library/Containers/uk.co.blackbox.logbook.UITests.xctrunner/Data/tmp", isDirectory: true)
        let candidate = runnerTemporaryDirectory
            .appendingPathComponent("Blackbox-XCUITest-\(UUID().uuidString)", isDirectory: true)

        let validated = try UITestLaunchConfiguration.validatedRoot(
            candidate.path,
            temporaryDirectory: systemTemporaryDirectory,
            homeDirectory: syntheticHome
        )

        #expect(validated == candidate.standardizedFileURL.resolvingSymlinksInPath())
    }

    @Test("Isolated UI-test home accepts only a direct synthetic data child")
    func isolatedUITestHomeAcceptsOnlyDirectSyntheticDataChild() throws {
        let syntheticRunnerHome = URL(fileURLWithPath: "/Users/Synthetic-Blackbox-Test", isDirectory: true)
        let runnerTemporaryDirectory = syntheticRunnerHome
            .appendingPathComponent("Library/Containers/uk.co.blackbox.logbook.UITests.xctrunner/Data/tmp", isDirectory: true)
        let isolatedHome = runnerTemporaryDirectory
            .appendingPathComponent("Blackbox-XCUITest-Home-\(UUID().uuidString)", isDirectory: true)
        let candidate = isolatedHome
            .appendingPathComponent("Blackbox-XCUITest-\(UUID().uuidString)", isDirectory: true)

        let validated = try UITestLaunchConfiguration.validatedRoot(
            candidate.path,
            temporaryDirectory: URL(fileURLWithPath: "/private/var/folders/target-process/T", isDirectory: true),
            homeDirectory: isolatedHome
        )
        #expect(validated == candidate.standardizedFileURL.resolvingSymlinksInPath())

        let targetTemporaryDirectory = URL(fileURLWithPath: "/private/var/folders/target-process/T", isDirectory: true)
        let targetTemporaryHome = targetTemporaryDirectory
            .appendingPathComponent("Blackbox-XCUITest-Home-\(UUID().uuidString)", isDirectory: true)
        let targetTemporaryCandidate = targetTemporaryHome
            .appendingPathComponent("Blackbox-XCUITest-\(UUID().uuidString)", isDirectory: true)
        let targetTemporaryValidated = try UITestLaunchConfiguration.validatedRoot(
            targetTemporaryCandidate.path,
            temporaryDirectory: targetTemporaryDirectory,
            homeDirectory: targetTemporaryHome
        )
        #expect(targetTemporaryValidated == targetTemporaryCandidate.standardizedFileURL.resolvingSymlinksInPath())

        let nested = candidate
            .appendingPathComponent("Nested/Blackbox-XCUITest-Nested", isDirectory: true)
        #expect(throws: (any Error).self) {
            _ = try UITestLaunchConfiguration.validatedRoot(
                nested.path,
                temporaryDirectory: URL(fileURLWithPath: "/private/var/folders/target-process/T", isDirectory: true),
                homeDirectory: isolatedHome
            )
        }

        let misleadingHome = URL(
            fileURLWithPath: "/Users/Synthetic-Blackbox-Test/Documents/Blackbox-XCUITest-Home-\(UUID().uuidString)",
            isDirectory: true
        )
        let misleadingCandidate = misleadingHome
            .appendingPathComponent("Blackbox-XCUITest-\(UUID().uuidString)", isDirectory: true)
        #expect(throws: (any Error).self) {
            _ = try UITestLaunchConfiguration.validatedRoot(
                misleadingCandidate.path,
                temporaryDirectory: URL(fileURLWithPath: "/private/var/folders/target-process/T", isDirectory: true),
                homeDirectory: misleadingHome
            )
        }
    }

    @Test("Nested, arbitrarily named, and live roots are rejected")
    func unsafeRootsAreRejected() {
        let syntheticHome = URL(fileURLWithPath: "/Users/Synthetic-Blackbox-Test", isDirectory: true)
        let systemTemporaryDirectory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
        let runnerTemporaryDirectory = syntheticHome
            .appendingPathComponent("Library/Containers/uk.co.blackbox.logbook.UITests.xctrunner/Data/tmp", isDirectory: true)
        let nestedCandidate = runnerTemporaryDirectory
            .appendingPathComponent("Nested/Blackbox-XCUITest-\(UUID().uuidString)", isDirectory: true)
        let arbitraryCandidate = runnerTemporaryDirectory
            .appendingPathComponent("Untrusted-\(UUID().uuidString)", isDirectory: true)
        let liveRoot = syntheticHome
            .appendingPathComponent("Library/Application Support/Blackbox", isDirectory: true)

        #expect(throws: (any Error).self) {
            _ = try UITestLaunchConfiguration.validatedRoot(
                nestedCandidate.path,
                temporaryDirectory: systemTemporaryDirectory,
                homeDirectory: syntheticHome
            )
        }
        #expect(throws: (any Error).self) {
            _ = try UITestLaunchConfiguration.validatedRoot(
                arbitraryCandidate.path,
                temporaryDirectory: systemTemporaryDirectory,
                homeDirectory: syntheticHome
            )
        }
        #expect(throws: (any Error).self) {
            _ = try UITestLaunchConfiguration.validatedRoot(
                liveRoot.path,
                temporaryDirectory: systemTemporaryDirectory,
                homeDirectory: syntheticHome
            )
        }
    }

    @Test("Existing unmarked root is rejected without deleting its contents")
    func existingUnmarkedRootIsRejectedWithoutDeletion() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("Blackbox-XCUITest-\(UUID().uuidString)", isDirectory: true)
        let sentinel = root.appendingPathComponent("must-remain.txt")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        try Data("synthetic sentinel\n".utf8).write(to: sentinel, options: .atomic)
        defer { try? fileManager.removeItem(at: root) }

        #expect(throws: (any Error).self) {
            try UITestLaunchConfiguration.resetMarkedRoot(root, fileManager: fileManager)
        }
        #expect(fileManager.fileExists(atPath: sentinel.path))
        #expect(try String(contentsOf: sentinel, encoding: .utf8) == "synthetic sentinel\n")
    }

    @Test("Empty comparison UI fixture is standalone and classified as empty")
    func emptyComparisonFixtureIsStandaloneAndClassifiedAsEmpty() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("Blackbox-XCUITest-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let paths = UITestLaunchConfiguration.pathsForCurrentLaunch(
            arguments: ["Blackbox", "--ui-testing"],
            environment: [
                "BLACKBOX_DATA_ROOT": root.path,
                "BLACKBOX_SYNTHETIC_FIXTURE": "deterministic",
                "BLACKBOX_UI_TEST_SCENARIO": "comparison-empty"
            ],
            fileManager: fileManager
        )

        #expect(fileManager.fileExists(atPath: paths.sourceLogTenDatabase.path))
        #expect(!fileManager.fileExists(atPath: paths.sourceLogTenDatabase.path + "-wal"))
        #expect(!fileManager.fileExists(atPath: paths.sourceLogTenDatabase.path + "-shm"))

        let source = try SQLiteConnection(path: paths.sourceLogTenDatabase.path, readOnly: true)
        let count = try source.rows("SELECT COUNT(*) AS count FROM ZFLIGHT").first?["count"]?.int
        #expect(count == 0)
        #expect(try source.integrityCheck().lowercased() == "ok")

        let repository = LogbookRepository(paths: paths)
        guard case .empty(let message) = repository.logTenComparisonState() else {
            Issue.record("A valid zero-row synthetic comparison fixture must be classified as empty")
            return
        }
        #expect(message.localizedCaseInsensitiveContains("no flights"))
    }

    @Test("Standard comparison fixture exactly matches its imported LogTen row")
    func standardComparisonFixtureIsAnExactImportedMatch() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("Blackbox-XCUITest-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let paths = UITestLaunchConfiguration.pathsForCurrentLaunch(
            arguments: ["Blackbox", "--ui-testing"],
            environment: [
                "BLACKBOX_DATA_ROOT": root.path,
                "BLACKBOX_SYNTHETIC_FIXTURE": "deterministic"
            ],
            fileManager: fileManager
        )

        let repository = LogbookRepository(paths: paths)
        guard case .loaded(let snapshot) = repository.logTenComparisonState() else {
            Issue.record("The standard synthetic comparison fixture must load")
            return
        }
        #expect(snapshot.importedRowsMatch)
        #expect(snapshot.issues.isEmpty)
        #expect(snapshot.logTen.copilotMinutes == 80)
        #expect(snapshot.logTen.copilotDayMinutes == 80)
        #expect(snapshot.blackboxImported.copilotDayMinutes == 80)
    }
}
