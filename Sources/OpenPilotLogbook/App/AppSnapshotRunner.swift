import AppKit
import SwiftUI

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
        let store = LogbookStore()
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

    private static func sectionByIdentifier(_ identifier: String) -> AppSection {
        switch identifier.lowercased() {
        case "flights": return .flights
        case "aircraft": return .aircraft
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
