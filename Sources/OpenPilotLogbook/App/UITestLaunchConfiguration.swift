import AppKit
import Foundation
import OpenPilotLogbookCore
import SwiftUI

/// Builds deterministic UI-test fixtures without ever resolving the production data root.
///
/// The application entry point must construct its store with
/// `LogbookStore(paths: UITestLaunchConfiguration.pathsForCurrentLaunch())`.
enum UITestLaunchConfiguration {
    static func allowsLiveLogTenDiscoveryForCurrentLaunch(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
#if DEBUG || APP_STORE
        return false
#else
        return !arguments.contains("--ui-testing") &&
            environment["BLACKBOX_DATA_ROOT"] == nil &&
            environment["OPENPILOT_SNAPSHOT_PATH"] == nil
#endif
    }
    private static let argument = "--ui-testing"
    private static let fixtureKey = "BLACKBOX_SYNTHETIC_FIXTURE"
    private static let scenarioKey = "BLACKBOX_UI_TEST_SCENARIO"
    private static let restoreFailureKey = "BLACKBOX_UI_TEST_RESTORE_FAILURE_STAGE"
    private static let saveFailureKey = "BLACKBOX_UI_TEST_SAVE_FAILURE"
    private static let folderSelectionKey = "BLACKBOX_UI_TEST_FOLDER_SELECTION"
    private static let folderSelectionArgumentPrefix = "--ui-testing-folder-selection="
    private static let rootKey = "BLACKBOX_DATA_ROOT"
    private static let snapshotKey = "OPENPILOT_SNAPSHOT_PATH"
    private static let markerName = ".blackbox-synthetic-ui-test-root"
    private static let markerContents = "Blackbox deterministic UI fixture\n"
    private static let allowedRootPrefixes = ["Blackbox-XCUITest-", "Blackbox-Xcode-Debug"]
    private static let isolatedUITestHomePrefix = "Blackbox-XCUITest-Home-"
    private static let uiTestRunnerBundleIdentifier = "uk.co.blackbox.logbook.UITests.xctrunner"
    private static let ephemeralLaunchPaths: LogbookPaths = makeEphemeralLaunchPaths()

    static func pathsForCurrentLaunch(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> LogbookPaths {
        let isUITest = arguments.contains(argument)
        let isSnapshot = !(environment[snapshotKey]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let requestedFixture = environment[fixtureKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawScenario = environment[scenarioKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawRestoreFailure = environment[restoreFailureKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawSaveFailure = environment[saveFailureKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawFolderSelection = syntheticFolderSelectionRequest(
            arguments: arguments,
            environment: environment
        )
        let requestedScenario = rawScenario.isEmpty ? "standard" : rawScenario.lowercased()

        guard isUITest else {
            precondition(requestedFixture.isEmpty, "\(fixtureKey) is test-only and requires \(argument).")
            precondition(rawScenario.isEmpty, "\(scenarioKey) is test-only and requires \(argument).")
            precondition(rawRestoreFailure.isEmpty, "\(restoreFailureKey) is test-only and requires \(argument).")
            precondition(rawSaveFailure.isEmpty, "\(saveFailureKey) is test-only and requires \(argument).")
            precondition(rawFolderSelection.isEmpty, "\(folderSelectionKey) is test-only and requires \(argument).")
            // A snapshot process constructs the app-level store before the
            // snapshot runner creates its own fixture. Point that otherwise
            // unused store at an application-generated temporary root.
            if isSnapshot { return ephemeralLaunchPaths }
#if DEBUG
            // Debug builds always fail closed onto a fresh process-owned root.
            // BLACKBOX_DATA_ROOT is deliberately ignored outside the validated
            // UI-test path so an arbitrary path can never become a debug store.
            return ephemeralLaunchPaths
#else
            // Direct-distribution builds use the real Application Support root.
            // Construct this explicitly because LogbookPaths.applicationSupport
            // also supports a CLI override that is inappropriate here.
            return productionPaths(fileManager: fileManager)
#endif
        }

        guard requestedFixture == "deterministic" else {
            preconditionFailure("UI tests require \(fixtureKey)=deterministic.")
        }
        guard rawFolderSelection.isEmpty || rawFolderSelection == "exports" else {
            preconditionFailure("Unsupported synthetic folder selection: \(rawFolderSelection)")
        }
        guard let rawRoot = environment[rootKey], !rawRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            preconditionFailure("UI tests require an isolated \(rootKey).")
        }

        do {
            let root = try validatedRoot(rawRoot, fileManager: fileManager)
            try resetMarkedRoot(root, fileManager: fileManager)
            let paths = LogbookPaths(
                backupFolder: root.appendingPathComponent("Backups", isDirectory: true),
                sourceLogTenDatabase: root
                    .appendingPathComponent("Import Sources", isDirectory: true)
                    .appendingPathComponent("LogTenCoreDataStore.sql"),
                workingDatabase: root.appendingPathComponent("Blackbox.sqlite")
            )
            try seedDeterministicFixture(at: paths, scenario: requestedScenario)
            return paths
        } catch {
            preconditionFailure("Refusing unsafe UI-test launch: \(error)")
        }
    }

    @MainActor
    static func configureApplicationIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard arguments.contains(argument) else { return }

        switch environment["BLACKBOX_UI_TEST_APPEARANCE"]?.lowercased() {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "contrast": NSApp.appearance = NSAppearance(named: .accessibilityHighContrastAqua)
        default: break
        }

        if environment["BLACKBOX_UI_TEST_REDUCE_MOTION"] == "1" {
            NSApp.windows.forEach { $0.animationBehavior = .none }
        }

        guard
            let widthText = environment["BLACKBOX_UI_TEST_WIDTH"],
            let heightText = environment["BLACKBOX_UI_TEST_HEIGHT"],
            let width = Double(widthText),
            let height = Double(heightText),
            width >= 860,
            height >= 740
        else { return }

        DispatchQueue.main.async {
            guard let window = NSApp.windows.first,
                  let screen = window.screen ?? NSScreen.main else { return }
            let requestedContent = NSRect(origin: .zero, size: NSSize(width: width, height: height))
            let requestedFrame = window.frameRect(forContentRect: requestedContent)
            let appliedFrame = fittedTestWindowFrame(requestedFrame: requestedFrame, visibleFrame: screen.visibleFrame)
            window.setFrame(appliedFrame, display: true)
        }
    }

    static func fittedTestWindowFrame(
        requestedFrame: NSRect,
        visibleFrame: NSRect,
        margin: CGFloat = 12
    ) -> NSRect {
        let safeFrame = visibleFrame.insetBy(dx: margin, dy: margin)
        let width = min(requestedFrame.width, safeFrame.width)
        let height = min(requestedFrame.height, safeFrame.height)
        return NSRect(
            x: safeFrame.midX - width / 2,
            y: safeFrame.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Returns a production repository failure-injection boundary only for a
    /// validated UI-test process. A leaked test-only value fails closed.
    static func restoreFailureStageForCurrentLaunch(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TransactionFailureStage? {
        let rawValue = environment[restoreFailureKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard arguments.contains(argument) else {
            precondition(rawValue.isEmpty, "\(restoreFailureKey) is test-only and requires \(argument).")
            return nil
        }
        guard !rawValue.isEmpty else { return nil }
        guard let stage = TransactionFailureStage(rawValue: rawValue) else {
            preconditionFailure("Unsupported synthetic restore failure stage: \(rawValue)")
        }
        return stage
    }

    /// A deterministic UI-only failure used to prove that choosing Save in an
    /// unsaved-navigation alert never discards or navigates after persistence
    /// fails. A leaked production value terminates before a store is opened.
    static func shouldInjectSaveFailureForCurrentLaunch(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let rawValue = environment[saveFailureKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard arguments.contains(argument) else {
            precondition(rawValue.isEmpty, "\(saveFailureKey) is test-only and requires \(argument).")
            return false
        }
        guard !rawValue.isEmpty else { return false }
        guard rawValue == "1" else {
            preconditionFailure("Unsupported synthetic save-failure value: \(rawValue)")
        }
        return true
    }

    /// Returns the one folder selection that hosted UI tests may inject when
    /// AppKit moves NSOpenPanel into its out-of-process panel service. The
    /// caller supplies only the fixed `exports` token; the destination is
    /// derived from the already validated, marked synthetic data root. Normal
    /// launches and every other folder choice continue through NSOpenPanel.
    static func syntheticFolderSelectionForCurrentLaunch(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        let rawValue = syntheticFolderSelectionRequest(
            arguments: arguments,
            environment: environment
        )
        guard arguments.contains(argument) else {
            precondition(rawValue.isEmpty, "\(folderSelectionKey) is test-only and requires \(argument).")
            return nil
        }
        guard !rawValue.isEmpty else { return nil }
        guard rawValue == "exports" else {
            preconditionFailure("Unsupported synthetic folder selection: \(rawValue)")
        }
        guard environment[fixtureKey]?.trimmingCharacters(in: .whitespacesAndNewlines) == "deterministic",
              let rawRoot = environment[rootKey],
              !rawRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            preconditionFailure("Synthetic folder selection requires the deterministic UI fixture and an isolated \(rootKey).")
        }

        do {
            let root = try validatedRoot(rawRoot, fileManager: fileManager)
            let marker = root.appendingPathComponent(markerName)
            guard try String(contentsOf: marker, encoding: .utf8) == markerContents else {
                preconditionFailure("Synthetic folder selection requires the marked UI-test root.")
            }
            let destination = root
                .appendingPathComponent("Exports", isDirectory: true)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard destination.deletingLastPathComponent() == root,
                  fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                preconditionFailure("Synthetic export selection must be an existing direct child of the UI-test root.")
            }
            return destination
        } catch {
            preconditionFailure("Refusing unsafe synthetic folder selection: \(error)")
        }
    }

    private static func syntheticFolderSelectionRequest(
        arguments: [String],
        environment: [String: String]
    ) -> String {
        let environmentValue = environment[folderSelectionKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let argumentValues = arguments.compactMap { argument -> String? in
            guard argument.hasPrefix(folderSelectionArgumentPrefix) else { return nil }
            return String(argument.dropFirst(folderSelectionArgumentPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        precondition(argumentValues.count <= 1, "UI tests accept only one synthetic folder-selection argument.")
        guard let argumentValue = argumentValues.first else { return environmentValue }
        precondition(
            environmentValue.isEmpty || environmentValue == argumentValue,
            "Conflicting synthetic folder-selection requests."
        )
        return argumentValue
    }

    static func validatedRoot(_ rawRoot: String, fileManager: FileManager) throws -> URL {
        try validatedRoot(
            rawRoot,
            temporaryDirectory: fileManager.temporaryDirectory,
            homeDirectory: fileManager.homeDirectoryForCurrentUser
        )
    }

    static func validatedRoot(
        _ rawRoot: String,
        temporaryDirectory: URL,
        homeDirectory: URL
    ) throws -> URL {
        let root = URL(fileURLWithPath: rawRoot, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let temporaryRoot = temporaryDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let temporaryPrefix = temporaryRoot.path.hasSuffix("/") ? temporaryRoot.path : temporaryRoot.path + "/"
        let canonicalHome = homeDirectory
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let uiTestRunnerTemporaryRoot = canonicalHome
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent(uiTestRunnerBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("tmp", isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let isDirectUITestRunnerTemporaryChild = root.deletingLastPathComponent() == uiTestRunnerTemporaryRoot
        let canonicalHomeParent = canonicalHome.deletingLastPathComponent()
        let isHomeBelowTargetTemporaryDirectory =
            canonicalHome.path.hasPrefix(temporaryPrefix) && canonicalHome.path != temporaryRoot.path
        let runnerSuffix = ["Library", "Containers", uiTestRunnerBundleIdentifier, "Data", "tmp"]
        let homeParentComponents = canonicalHomeParent.pathComponents
        let isHomeBelowUITestRunnerTemporaryDirectory =
            homeParentComponents.count == 8
                && homeParentComponents[1] == "Users"
                && Array(homeParentComponents.suffix(runnerSuffix.count)) == runnerSuffix
        let isRecognizedIsolatedUITestHome =
            canonicalHome.lastPathComponent.hasPrefix(isolatedUITestHomePrefix)
                && (isHomeBelowTargetTemporaryDirectory || isHomeBelowUITestRunnerTemporaryDirectory)
        let isDirectIsolatedUITestHomeChild =
            isRecognizedIsolatedUITestHome && root.deletingLastPathComponent() == canonicalHome

        guard
            (root.path.hasPrefix(temporaryPrefix) && root.path != temporaryRoot.path)
                || isDirectUITestRunnerTemporaryChild
                || isDirectIsolatedUITestHomeChild
        else {
            throw FixtureError.rootOutsideTemporaryDirectory(root.path)
        }
        guard allowedRootPrefixes.contains(where: root.lastPathComponent.hasPrefix) else {
            throw FixtureError.invalidRootName(root.lastPathComponent)
        }

        let liveRoot = canonicalHome
            .appendingPathComponent("Library/Application Support/Blackbox", isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard root.path != liveRoot.path else {
            throw FixtureError.productionRootRejected
        }
        return root
    }

    private static func makeEphemeralLaunchPaths(fileManager: FileManager = .default) -> LogbookPaths {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("Blackbox-Debug-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
            try Data("Blackbox process-owned temporary launch root\n".utf8)
                .write(to: root.appendingPathComponent(markerName), options: .atomic)
        } catch {
            preconditionFailure("Could not create a safe temporary Blackbox launch root: \(error)")
        }
        return paths(rootedAt: root)
    }

    private static func productionPaths(fileManager: FileManager) -> LogbookPaths {
        let root = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Blackbox", isDirectory: true)
        return paths(rootedAt: root)
    }

    private static func paths(rootedAt root: URL) -> LogbookPaths {
        LogbookPaths(
            backupFolder: root.appendingPathComponent("Backups", isDirectory: true),
            sourceLogTenDatabase: root
                .appendingPathComponent("Import Sources", isDirectory: true)
                .appendingPathComponent("LogTenCoreDataStore.sql"),
            workingDatabase: root.appendingPathComponent("Blackbox.sqlite")
        )
    }

    static func resetMarkedRoot(_ root: URL, fileManager: FileManager) throws {
        let marker = root.appendingPathComponent(markerName)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw FixtureError.rootIsNotDirectory(root.path) }
            guard fileManager.fileExists(atPath: marker.path) else {
                throw FixtureError.unmarkedExistingRoot(root.path)
            }
            try fileManager.removeItem(at: root)
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
        try Data(markerContents.utf8).write(to: marker, options: .atomic)
    }

    private static func seedDeterministicFixture(at paths: LogbookPaths, scenario: String) throws {
        guard ["standard", "comparison-missing", "comparison-unreadable", "comparison-empty", "comparison-different", "comparison-match"].contains(scenario) else {
            throw FixtureError.invalidScenario(scenario)
        }
        let repository = LogbookRepository(paths: paths)
        try repository.bootstrapIfNeeded()

        let imported = FlightEntry(
            sourcePK: 1_001,
            date: fixedDate(year: 2026, month: 6, day: 14, hour: 8, minute: 15),
            departure: "EGLL",
            arrival: "EHAM",
            route: "DCT",
            aircraftID: "G-BBX1",
            aircraftType: "A320",
            flightNumber: "BX104",
            operation: "MP",
            entryKind: "",
            pilotFunction: "",
            totalMinutes: 80,
            copilotMinutes: 80,
            copilotDayMinutes: 80,
            instrumentMinutes: 22,
            crossCountryMinutes: 80,
            pilotFlying: true,
            dayTakeoffs: 1,
            totalTakeoffs: 1,
            dayLandings: 1,
            totalLandings: 1,
            passengerCount: 144,
            distanceNM: 231,
            departureLatitude: 51.4700,
            departureLongitude: -0.4543,
            arrivalLatitude: 52.3105,
            arrivalLongitude: 4.7683,
            remarks: "Synthetic imported fixture"
        )
        let importedID = try repository.saveDraft(imported, origin: "ui_test_fixture")
        guard var importedDraft = try repository.flight(id: importedID) else {
            throw FixtureError.seededFlightMissing(importedID)
        }
        importedDraft.id = importedID
        _ = try repository.finalise(importedDraft, acknowledgeWarnings: true, origin: "ui_test_fixture")

        let editable = FlightEntry(
            date: fixedDate(year: 2026, month: 6, day: 20, hour: 19, minute: 40),
            departure: "EHAM",
            arrival: "EDDF",
            route: "DCT",
            aircraftID: "G-BBX2",
            aircraftType: "A321",
            flightNumber: "BX218",
            operation: "MP",
            pilotFunction: "Co-pilot",
            totalMinutes: 95,
            copilotMinutes: 0,
            instrumentMinutes: 18,
            crossCountryMinutes: 95,
            distanceNM: 226,
            departureLatitude: 52.3105,
            departureLongitude: 4.7683,
            arrivalLatitude: 50.0379,
            arrivalLongitude: 8.5622,
            remarks: "Synthetic editable fixture"
        )
        _ = try repository.saveDraft(editable, origin: "ui_test_fixture")

        let suggestionFlight = FlightEntry(
            date: fixedDate(year: 2026, month: 1, day: 15, hour: 23, minute: 10),
            departure: "EGLL",
            arrival: "EHAM",
            route: "DCT",
            aircraftID: "G-BBX4",
            aircraftType: "A320",
            flightNumber: "BX-NIGHT",
            operation: "MP",
            pilotFunction: "Co-pilot",
            totalMinutes: 80,
            crossCountryMinutes: 80,
            distanceNM: 231,
            departureLatitude: 51.4700,
            departureLongitude: -0.4543,
            arrivalLatitude: 52.3105,
            arrivalLongitude: 4.7683,
            remarks: "Synthetic night and role suggestion fixture"
        )
        _ = try repository.saveDraft(suggestionFlight, origin: "ui_test_fixture")

        let recoverable = FlightEntry(
            date: fixedDate(year: 2026, month: 6, day: 25, hour: 10, minute: 5),
            departure: "EDDF",
            arrival: "LIRF",
            aircraftID: "G-BBX1",
            aircraftType: "A320",
            flightNumber: "BX302",
            operation: "MP",
            pilotFunction: "Co-pilot",
            totalMinutes: 112,
            copilotMinutes: 112,
            copilotDayMinutes: 112,
            crossCountryMinutes: 112,
            remarks: "Synthetic recoverable fixture"
        )
        let recoverableID = try repository.saveDraft(recoverable, origin: "ui_test_fixture")
        try repository.moveToTrash(id: recoverableID, origin: "ui_test_fixture")
        var secondRecoverable = recoverable
        secondRecoverable.flightNumber = "BX303"
        secondRecoverable.arrival = "LCLK"
        secondRecoverable.remarks = "Second synthetic recoverable fixture"
        let secondRecoverableID = try repository.saveDraft(secondRecoverable, origin: "ui_test_fixture")
        try repository.moveToTrash(id: secondRecoverableID, origin: "ui_test_fixture")

        try createLogTenFixture(at: paths.sourceLogTenDatabase, matching: imported)
        var changedImport = imported
        changedImport.flightNumber = "BX104A"
        changedImport.totalMinutes = 85
        changedImport.copilotMinutes = 85
        changedImport.copilotDayMinutes = 85
        changedImport.crossCountryMinutes = 85
        let differentSource = paths.sourceLogTenDatabase.deletingLastPathComponent().appendingPathComponent("LogTenImportChanges.sql")
        try createLogTenFixture(at: differentSource, matching: changedImport)
        let emptySource = paths.sourceLogTenDatabase.deletingLastPathComponent().appendingPathComponent("LogTenEmpty.sql")
        try createLogTenFixture(at: emptySource, matching: imported)
        let emptyDatabase = try SQLiteConnection(path: emptySource.path)
        try emptyDatabase.execute("DELETE FROM ZFLIGHT")
        try emptyDatabase.finalizeAsSelfContainedDatabase()
        let unreadableSource = paths.sourceLogTenDatabase.deletingLastPathComponent().appendingPathComponent("LogTenUnreadable.sql")
        try Data("This is an intentionally unreadable synthetic comparison fixture.\n".utf8).write(
            to: unreadableSource,
            options: .atomic
        )
        try configureComparisonScenario(
            scenario,
            configuredSource: paths.sourceLogTenDatabase,
            differentSource: differentSource,
            emptySource: emptySource,
            unreadableSource: unreadableSource
        )
        let documentFixture = paths.workingDatabase.deletingLastPathComponent().appendingPathComponent("Synthetic-Document-Import.csv")
        try Data("Date,Departure,Arrival,Aircraft,Total\n2026-06-28,EGLL,EDDF,G-BBX3,01:25\n".utf8)
            .write(to: documentFixture, options: .atomic)
        try FileManager.default.createDirectory(
            at: paths.workingDatabase.deletingLastPathComponent().appendingPathComponent("Exports", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private static func configureComparisonScenario(
        _ scenario: String,
        configuredSource: URL,
        differentSource: URL,
        emptySource: URL,
        unreadableSource: URL
    ) throws {
        let replacement: URL?
        switch scenario {
        case "standard", "comparison-match": replacement = nil
        case "comparison-missing":
            try FileManager.default.removeItem(at: configuredSource)
            return
        case "comparison-unreadable": replacement = unreadableSource
        case "comparison-empty": replacement = emptySource
        case "comparison-different": replacement = differentSource
        default: throw FixtureError.invalidScenario(scenario)
        }
        guard let replacement else { return }
        try replaceSyntheticDatabase(at: configuredSource, with: replacement)
    }

    private static func replaceSyntheticDatabase(at destination: URL, with source: URL) throws {
        let fileManager = FileManager.default
        let staged = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).replacement")
        defer { try? fileManager.removeItem(at: staged) }

        try fileManager.copyItem(at: source, to: staged)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: destination.path + suffix)
            if fileManager.fileExists(atPath: sidecar.path) {
                try fileManager.removeItem(at: sidecar)
            }
        }
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
        } else {
            try fileManager.moveItem(at: staged, to: destination)
        }
    }

    private static func fixedDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private static func createLogTenFixture(at url: URL, matching flight: FlightEntry) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let database = try SQLiteConnection(path: url.path)
        try database.execute("""
            CREATE TABLE ZAIRCRAFTTYPE (
                Z_PK INTEGER PRIMARY KEY,
                ZAIRCRAFTTYPE_TYPE TEXT,
                ZAIRCRAFTTYPE_MODEL TEXT
            )
            """)
        try database.execute("""
            CREATE TABLE ZAIRCRAFT (
                Z_PK INTEGER PRIMARY KEY,
                ZAIRCRAFT_AIRCRAFTID TEXT,
                ZAIRCRAFT_AIRCRAFTTYPE INTEGER
            )
            """)
        try database.execute("""
            CREATE TABLE ZPLACE (
                Z_PK INTEGER PRIMARY KEY,
                ZPLACE_IDENTIFIER TEXT,
                ZPLACE_ICAOID TEXT,
                ZPLACE_IATAID TEXT,
                ZPLACE_LAT REAL,
                ZPLACE_LON REAL
            )
            """)
        try database.execute("""
            CREATE TABLE ZPERSON (
                Z_PK INTEGER PRIMARY KEY,
                ZPERSON_FIRSTNAME TEXT,
                ZPERSON_LASTNAME TEXT,
                ZPERSON_FULLNAME TEXT,
                ZPERSON_NAME TEXT
            )
            """)
        try database.execute("""
            CREATE TABLE ZFLIGHTCREW (
                Z_PK INTEGER PRIMARY KEY,
                ZFLIGHTCREW_FLIGHT INTEGER,
                ZFLIGHTCREW_PIC INTEGER,
                ZFLIGHTCREW_SIC INTEGER,
                ZFLIGHTCREW_COMMANDER INTEGER,
                ZFLIGHTCREW_INSTRUCTOR INTEGER,
                ZFLIGHTCREW_FLIGHTENGINEER INTEGER,
                ZFLIGHTCREW_PURSER INTEGER,
                ZFLIGHTCREW_RELIEF1 INTEGER,
                ZFLIGHTCREW_RELIEF2 INTEGER,
                ZFLIGHTCREW_RELIEF3 INTEGER,
                ZFLIGHTCREW_RELIEF4 INTEGER,
                ZFLIGHTCREW_STUDENT INTEGER
            )
            """)
        try database.execute("""
            CREATE TABLE ZFLIGHT (
                Z_PK INTEGER PRIMARY KEY,
                ZFLIGHT_FLIGHTDATE REAL,
                ZFLIGHT_FROMPLACE INTEGER,
                ZFLIGHT_TOPLACE INTEGER,
                ZFLIGHT_ROUTE TEXT,
                ZFLIGHT_AIRCRAFT INTEGER,
                ZFLIGHT_AIRCRAFTTYPE INTEGER,
                ZFLIGHT_FLIGHTNUMBER TEXT,
                ZFLIGHT_MULTIPILOT INTEGER,
                ZFLIGHT_TOTALTIME INTEGER,
                ZFLIGHT_PIC INTEGER,
                ZFLIGHT_PICNIGHT INTEGER,
                ZFLIGHT_P1US INTEGER,
                ZFLIGHT_CUSTOMTIME4 INTEGER,
                ZFLIGHT_P1USNIGHT INTEGER,
                ZFLIGHT_CUSTOMTIME3 INTEGER,
                ZFLIGHT_DUALRECEIVED INTEGER,
                ZFLIGHT_SFI INTEGER,
                ZFLIGHT_DUALGIVEN INTEGER,
                ZFLIGHT_NIGHT INTEGER,
                ZFLIGHT_CUSTOMTIME2 INTEGER,
                ZFLIGHT_CROSSCOUNTRY INTEGER,
                ZFLIGHT_SIMULATOR INTEGER,
                ZFLIGHT_PILOTFLYINGCAPACITY INTEGER,
                ZFLIGHT_DAYTAKEOFFS INTEGER,
                ZFLIGHT_NIGHTTAKEOFFS INTEGER,
                ZFLIGHT_TOTALTAKEOFFS INTEGER,
                ZFLIGHT_DAYLANDINGS INTEGER,
                ZFLIGHT_NIGHTLANDINGS INTEGER,
                ZFLIGHT_TOTALLANDINGS INTEGER,
                ZFLIGHT_PAXCOUNT INTEGER,
                ZFLIGHT_DISTANCE REAL,
                ZFLIGHT_REMARKS TEXT
            )
            """)

        try database.execute("INSERT INTO ZAIRCRAFTTYPE VALUES (1, ?, ?)", values: [.text(flight.aircraftType), .text(flight.aircraftType)])
        try database.execute("INSERT INTO ZAIRCRAFT VALUES (1, ?, 1)", values: [.text(flight.aircraftID)])
        try database.execute("INSERT INTO ZPLACE VALUES (1, ?, ?, '', ?, ?)", values: [
            .text(flight.departure), .text(flight.departure),
            flight.departureLatitude.map(SQLiteValue.real) ?? .null,
            flight.departureLongitude.map(SQLiteValue.real) ?? .null
        ])
        try database.execute("INSERT INTO ZPLACE VALUES (2, ?, ?, '', ?, ?)", values: [
            .text(flight.arrival), .text(flight.arrival),
            flight.arrivalLatitude.map(SQLiteValue.real) ?? .null,
            flight.arrivalLongitude.map(SQLiteValue.real) ?? .null
        ])
        try database.execute("""
            INSERT INTO ZFLIGHT VALUES (
                ?, ?, 1, 2, ?, 1, 1, ?, 1,
                ?, 0, 0, 0, 0, 0, ?, 0, 0, 0, ?, ?, ?, 0, ?,
                ?, ?, ?, ?, ?, ?, ?, ?, ?
            )
            """, values: [
                .integer(flight.sourcePK ?? 1_001),
                .real(flight.date.timeIntervalSinceReferenceDate),
                .text(flight.route),
                .text(flight.flightNumber),
                .integer(Int64(flight.totalMinutes)),
                .integer(Int64(flight.copilotMinutes)),
                .integer(Int64(flight.nightMinutes)),
                .integer(Int64(flight.instrumentMinutes)),
                .integer(Int64(flight.crossCountryMinutes)),
                .integer(flight.pilotFlying ? 1 : 0),
                .integer(Int64(flight.dayTakeoffs)),
                .integer(Int64(flight.nightTakeoffs)),
                .integer(Int64(flight.totalTakeoffs)),
                .integer(Int64(flight.dayLandings)),
                .integer(Int64(flight.nightLandings)),
                .integer(Int64(flight.totalLandings)),
                .integer(Int64(flight.passengerCount)),
                .real(flight.distanceNM),
                .text(flight.remarks)
            ])
        try database.finalizeAsSelfContainedDatabase()
    }

    private enum FixtureError: LocalizedError {
        case rootOutsideTemporaryDirectory(String)
        case invalidRootName(String)
        case productionRootRejected
        case rootIsNotDirectory(String)
        case unmarkedExistingRoot(String)
        case seededFlightMissing(Int64)
        case invalidScenario(String)

        var errorDescription: String? {
            switch self {
            case .rootOutsideTemporaryDirectory(let path): return "Root is not inside the system temporary directory: \(path)"
            case .invalidRootName(let name): return "Unexpected test-root name: \(name)"
            case .productionRootRejected: return "The production Application Support root is never valid for UI tests."
            case .rootIsNotDirectory(let path): return "Test root is not a directory: \(path)"
            case .unmarkedExistingRoot(let path): return "Existing test root has no synthetic marker and will not be removed: \(path)"
            case .seededFlightMissing(let id): return "Seeded flight \(id) could not be read back."
            case .invalidScenario(let scenario): return "Unsupported synthetic UI-test scenario: \(scenario)"
            }
        }
    }
}

/// Applies accessibility variants only to deterministic UI-test launches.
/// Production launches take the unmodified system environment branch.
struct UITestAccessibilityEnvironment: ViewModifier {
    private let environment = ProcessInfo.processInfo.environment
    private let isUITest = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    @ViewBuilder
    func body(content: Content) -> some View {
        if isUITest {
            content
                .environment(\.dynamicTypeSize, dynamicTypeSize)
                .environment(\.blackboxReduceMotionOverride, reduceMotion)
        } else {
            content
        }
    }

    private var dynamicTypeSize: DynamicTypeSize {
        switch environment["BLACKBOX_UI_TEST_DYNAMIC_TYPE_SIZE"]?.lowercased() {
        case "accessibility3": return .accessibility3
        case "xxlarge": return .xxLarge
        default: return .large
        }
    }

    private var reduceMotion: Bool {
        environment["BLACKBOX_UI_TEST_REDUCE_MOTION"] == "1"
    }
}

private struct BlackboxReduceMotionOverrideKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var blackboxReduceMotionOverride: Bool {
        get { self[BlackboxReduceMotionOverrideKey.self] }
        set { self[BlackboxReduceMotionOverrideKey.self] = newValue }
    }
}
