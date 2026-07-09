import CryptoKit
import Foundation

public enum EncryptedBackupService {
    public static func createBackup(database: URL, destinationFolder: URL, passphrase: String) throws -> BackupResult {
        guard !passphrase.isEmpty else {
            throw NSError(domain: "BlackboxBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter a backup passphrase."])
        }
        guard FileManager.default.fileExists(atPath: database.path) else {
            throw NSError(domain: "BlackboxBackup", code: 2, userInfo: [NSLocalizedDescriptionKey: "The working database could not be found."])
        }
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let stamp = backupStamp()
        let encryptedURL = destinationFolder.appendingPathComponent("Blackbox_Encrypted_Backup_\(stamp).blackboxbackup")
        let manifestURL = destinationFolder.appendingPathComponent("Blackbox_Encrypted_Backup_\(stamp).manifest.json")
        let sourceData = try Data(contentsOf: database)
        let sealed = try AES.GCM.seal(sourceData, using: key(from: passphrase))
        guard let combined = sealed.combined else {
            throw NSError(domain: "BlackboxBackup", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create encrypted backup payload."])
        }
        try combined.write(to: encryptedURL, options: [.atomic])
        let manifest = """
        {
          "application": "Blackbox",
          "format": "blackbox-encrypted-sqlite",
          "version": 1,
          "createdAt": "\(LogbookFormatters.isoFormatter.string(from: Date()))",
          "payload": "\(encryptedURL.lastPathComponent)",
          "privacy": "Encrypted database payload only. This manifest intentionally contains no flight rows or personal logbook data."
        }
        """
        try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
        return BackupResult(encryptedBackup: encryptedURL, manifest: manifestURL)
    }

    public static func restoreBackup(encryptedBackup: URL, destinationDatabase: URL, passphrase: String) throws {
        guard !passphrase.isEmpty else {
            throw NSError(domain: "BlackboxBackup", code: 4, userInfo: [NSLocalizedDescriptionKey: "Enter the backup passphrase."])
        }
        let data = try Data(contentsOf: encryptedBackup)
        let sealed = try AES.GCM.SealedBox(combined: data)
        let plaintext = try AES.GCM.open(sealed, using: key(from: passphrase))
        try FileManager.default.createDirectory(at: destinationDatabase.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plaintext.write(to: destinationDatabase, options: [.atomic])
    }

    private static func key(from passphrase: String) -> SymmetricKey {
        let digest = SHA256.hash(data: Data(passphrase.utf8))
        return SymmetricKey(data: Data(digest))
    }

    private static func backupStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
