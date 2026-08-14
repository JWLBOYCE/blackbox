import Foundation

/// Durable, flight-free diagnostics used only when SQLite operation-history
/// recording is unavailable. These JSON files can be imported into History on
/// a later healthy launch without opening or changing any flight row.
public enum OperationAuditStore {
    public static func store(_ batch: OperationBatch, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeID = batch.id.replacingOccurrences(of: "/", with: "-")
        let url = folder.appendingPathComponent("Failed-Operation-\(safeID).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(batch).write(to: url, options: [.atomic])
        return url
    }

    public static func pending(in folder: URL) throws -> [(url: URL, batch: OperationBatch)] {
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { ($0, try decoder.decode(OperationBatch.self, from: Data(contentsOf: $0))) }
    }

    /// Moves an imported diagnostic out of the pending queue while retaining
    /// it as a recovery artifact. This avoids replaying the same item on every
    /// healthy launch without permanently deleting diagnostic evidence.
    @discardableResult
    public static func markImported(_ url: URL) throws -> URL {
        let importedFolder = url.deletingLastPathComponent()
            .appendingPathComponent("Imported", isDirectory: true)
        try FileManager.default.createDirectory(at: importedFolder, withIntermediateDirectories: true)
        var destination = importedFolder.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = importedFolder.appendingPathComponent(
                "\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).json"
            )
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}
