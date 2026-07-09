import Foundation

public enum PrivacyGuard {
    private static let allowedTrackedPaths: Set<String> = [
        "Sources/OpenPilotLogbookCore/Services/SQLiteConnection.swift",
        "Sources/OpenPilotLogbookCore/Resources/airports.csv"
    ]

    private static let blockedExtensions: Set<String> = [
        "sqlite", "db", "sql", "pdf", "numbers", "xlsx", "xls", "heic", "tiff"
    ]

    public static func blockedTrackedPaths(_ paths: [String]) -> [String] {
        paths.filter { path in
            guard !allowedTrackedPaths.contains(path) else { return false }
            let lower = path.lowercased()
            if lower.contains("logtencoredatastore") { return true }
            if lower.contains("openpilotlogbook.sqlite") { return true }
            if lower.contains("roster") { return true }
            let ext = URL(fileURLWithPath: lower).pathExtension
            if blockedExtensions.contains(ext) { return true }
            if ext == "csv" && path != "Sources/OpenPilotLogbookCore/Resources/airports.csv" { return true }
            return false
        }
        .sorted()
    }
}
