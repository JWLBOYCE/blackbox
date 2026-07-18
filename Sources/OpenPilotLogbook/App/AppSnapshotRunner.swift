import AppKit
import SwiftUI
import OpenPilotLogbookCore

enum AppSnapshotRunner {
    @MainActor
    static func runIfRequested() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let outputPath = environment["OPENPILOT_SNAPSHOT_PATH"], !outputPath.isEmpty else {
            return false
        }

        Task { @MainActor in
            do {
                try renderSnapshot(
                    outputPath: outputPath,
                    section: environment["OPENPILOT_SNAPSHOT_SECTION"] ?? "dashboard",
                    width: Int(environment["OPENPILOT_SNAPSHOT_WIDTH"] ?? "") ?? 1440,
                    height: Int(environment["OPENPILOT_SNAPSHOT_HEIGHT"] ?? "") ?? 980
                )
                NSApp.terminate(nil)
            } catch {
                fputs("OpenPilot snapshot failed: \(error)\n", stderr)
                NSApp.terminate(nil)
            }
        }
        return true
    }

    @MainActor
    private static func renderSnapshot(outputPath: String, section: String, width: Int, height: Int) throws {
        let snapshotRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("Blackbox-Snapshot-\(UUID().uuidString)", isDirectory: true)
        let paths = LogbookPaths(
            backupFolder: snapshotRoot.appendingPathComponent("Backups", isDirectory: true),
            sourceLogTenDatabase: snapshotRoot.appendingPathComponent("Sample-LogTen.sql"),
            workingDatabase: snapshotRoot.appendingPathComponent("Blackbox-Sample.sqlite")
        )
        defer { try? FileManager.default.removeItem(at: snapshotRoot) }

        try FileManager.default.createDirectory(at: snapshotRoot, withIntermediateDirectories: true)
        try seedPrivacySafeSampleData(at: paths)
        let store = LogbookStore(paths: paths)
        store.selectedSection = AppSection(rawValue: section) ?? sectionByIdentifier(section)
        if store.selectedSection == .comparison {
            store.refreshLogTenComparison()
        }

        let size = CGSize(width: width, height: height)
        let view = NSHostingView(rootView: ContentView(store: store).frame(width: size.width, height: size.height))
        view.appearance = NSAppearance(named: .darkAqua)
        view.frame = CGRect(origin: .zero, size: size)
        view.wantsLayer = true
        view.layoutSubtreeIfNeeded()

        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw SnapshotError.bitmapCreation
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.pngEncoding
        }

        let url = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try pngData.write(to: url, options: .atomic)
    }

    private static func seedPrivacySafeSampleData(at paths: LogbookPaths) throws {
        let repository = LogbookRepository(paths: paths)
        try repository.bootstrapIfNeeded()
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let airports: [String: (Double, Double)] = [
            "EGLL": (51.4700, -0.4543), "EHAM": (52.3105, 4.7683),
            "EDDF": (50.0379, 8.5622), "LIRF": (41.8003, 12.2389),
            "LEMD": (40.4983, -3.5676), "LPPT": (38.7742, -9.1342),
            "LSZH": (47.4581, 8.5555), "EKCH": (55.6181, 12.6560),
            "ENGM": (60.1939, 11.1004), "LOWW": (48.1103, 16.5697),
            "LFMN": (43.6653, 7.2150), "EIDW": (53.4213, -6.2701)
        ]
        let sectors: [(Int, String, String, String, Int, Double, Bool)] = [
            (2, "EGLL", "EHAM", "BX104", 78, 231, false),
            (5, "EHAM", "EGLL", "BX105", 82, 231, true),
            (9, "EGLL", "EDDF", "BX218", 96, 354, false),
            (14, "EDDF", "LIRF", "BX219", 112, 518, true),
            (21, "LIRF", "EGLL", "BX302", 154, 778, false),
            (32, "EGLL", "LEMD", "BX411", 138, 674, false),
            (47, "LEMD", "LPPT", "BX412", 74, 277, true),
            (63, "LPPT", "EGLL", "BX413", 148, 841, false),
            (81, "EGLL", "LSZH", "BX520", 101, 424, false),
            (104, "LSZH", "EKCH", "BX521", 118, 512, true),
            (137, "EKCH", "ENGM", "BX604", 69, 280, false),
            (171, "LOWW", "LFMN", "BX703", 107, 468, false),
            (214, "LFMN", "EIDW", "BX704", 156, 786, true),
            (268, "EIDW", "EGLL", "BX705", 71, 243, false)
        ]

        for (index, sector) in sectors.enumerated() {
            let (daysAgo, departure, arrival, flightNumber, duration, distance, isNight) = sector
            let departureCoordinate = airports[departure]!
            let arrivalCoordinate = airports[arrival]!
            let nightMinutes = isNight ? min(duration, 46) : 0
            let dayMinutes = duration - nightMinutes
            let flight = FlightEntry(
                date: calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today,
                departure: departure,
                arrival: arrival,
                route: "DCT",
                aircraftID: index.isMultiple(of: 2) ? "G-BBX1" : "G-BBX2",
                aircraftType: index.isMultiple(of: 3) ? "A320" : "A321",
                flightNumber: flightNumber,
                operation: "MP",
                entryKind: "Flight",
                pilotFunction: "Co-pilot",
                totalMinutes: duration,
                copilotMinutes: duration,
                copilotDayMinutes: dayMinutes,
                copilotNightMinutes: nightMinutes,
                nightMinutes: nightMinutes,
                instrumentMinutes: min(duration, 24 + index * 2),
                crossCountryMinutes: duration,
                pilotFlying: index.isMultiple(of: 2),
                dayTakeoffs: isNight ? 0 : 1,
                nightTakeoffs: isNight ? 1 : 0,
                totalTakeoffs: 1,
                dayLandings: isNight ? 0 : 1,
                nightLandings: isNight ? 1 : 0,
                totalLandings: 1,
                passengerCount: 118 + index * 4,
                distanceNM: distance,
                crewNames: "Sample Captain | Sample First Officer",
                crewRoles: "Sample Captain=Captain | Sample First Officer=First Officer",
                departureLatitude: departureCoordinate.0,
                departureLongitude: departureCoordinate.1,
                arrivalLatitude: arrivalCoordinate.0,
                arrivalLongitude: arrivalCoordinate.1,
                remarks: "Synthetic demonstration record"
            )
            _ = try repository.save(flight)
        }
    }

    private static func sectionByIdentifier(_ identifier: String) -> AppSection {
        switch identifier.lowercased() {
        case "flights": return .flights
        case "pages", "logbook-pages": return .pages
        case "aircraft": return .aircraft
        case "people", "crew": return .people
        case "analysis": return .analysis
        case "map", "3d-map", "3d map": return .map
        case "comparison", "compare", "logten": return .comparison
        case "imports", "import": return .imports
        case "compliance", "caa", "caa-check": return .compliance
        case "reports": return .reports
        default: return .dashboard
        }
    }

    private enum SnapshotError: Error {
        case bitmapCreation
        case pngEncoding
    }
}
