import CommonCrypto
import CryptoKit
import Foundation

public enum EncryptedBackupService {
    private static let envelopeMagic = Data("BLACKBOX-ENCRYPTED-BACKUP".utf8)
    private static let envelopeVersion: UInt8 = 2
    private static let saltBytes = 16
    private static let keyBytes = 32
    private static let pbkdf2Iterations: UInt32 = 600_000
    private static let maximumBackupBytes = 1_073_741_824

    public static func createBackup(database: URL, destinationFolder: URL, passphrase: String) throws -> BackupResult {
        guard passphrase.count >= 12 else {
            throw NSError(domain: "BlackboxBackup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Use a backup passphrase of at least 12 characters."])
        }
        guard FileManager.default.fileExists(atPath: database.path) else {
            throw NSError(domain: "BlackboxBackup", code: 2, userInfo: [NSLocalizedDescriptionKey: "The working database could not be found."])
        }
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        let stamp = backupStamp()
        let encryptedURL = destinationFolder.appendingPathComponent("Blackbox_Encrypted_Backup_\(stamp).blackboxbackup")
        let manifestURL = destinationFolder.appendingPathComponent("Blackbox_Encrypted_Backup_\(stamp).manifest.json")
        let sourceData = try selfContainedPayload(from: database)
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        let sealed = try AES.GCM.seal(sourceData, using: derivedKey(from: passphrase, salt: salt, iterations: pbkdf2Iterations))
        guard let combined = sealed.combined else {
            throw NSError(domain: "BlackboxBackup", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create encrypted backup payload."])
        }
        try envelope(salt: salt, iterations: pbkdf2Iterations, sealedPayload: combined).write(to: encryptedURL, options: [.atomic])
        let manifest = """
        {
          "application": "Blackbox",
          "format": "blackbox-encrypted-sqlite",
          "version": 2,
          "createdAt": "\(LogbookFormatters.isoFormatter.string(from: Date()))",
          "payload": "\(encryptedURL.lastPathComponent)",
          "encryption": "AES-256-GCM",
          "keyDerivation": "PBKDF2-HMAC-SHA256",
          "keyDerivationIterations": \(pbkdf2Iterations),
          "privacy": "Encrypted database payload only. This manifest intentionally contains no flight rows or personal logbook data."
        }
        """
        try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
        return BackupResult(encryptedBackup: encryptedURL, manifest: manifestURL)
    }

    public static func restoreBackup(encryptedBackup: URL, destinationDatabase: URL, passphrase: String) throws {
        try decryptBackup(encryptedBackup: encryptedBackup, destinationDatabase: destinationDatabase, passphrase: passphrase)
    }

    public static func decryptBackup(encryptedBackup: URL, destinationDatabase: URL, passphrase: String) throws {
        guard !passphrase.isEmpty else {
            throw NSError(domain: "BlackboxBackup", code: 4, userInfo: [NSLocalizedDescriptionKey: "Enter the backup passphrase."])
        }
        let values = try encryptedBackup.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= maximumBackupBytes else {
            throw backupError(code: 12, message: "The encrypted backup is not a regular file within the 1 GiB safety limit.")
        }
        let data = try Data(contentsOf: encryptedBackup)
        let key: SymmetricKey
        let sealedPayload: Data
        if data.starts(with: envelopeMagic) {
            let parsed = try parseEnvelope(data)
            key = try derivedKey(from: passphrase, salt: parsed.salt, iterations: parsed.iterations)
            sealedPayload = parsed.sealedPayload
        } else {
            // Version 1 backups used a single SHA-256 pass over the passphrase.
            // Keep restore compatibility, but never create new backups in that format.
            key = legacyKey(from: passphrase)
            sealedPayload = data
        }
        let sealed = try AES.GCM.SealedBox(combined: sealedPayload)
        let plaintext = try AES.GCM.open(sealed, using: key)
        guard plaintext.count <= maximumBackupBytes else {
            throw backupError(code: 13, message: "The decrypted backup exceeds the 1 GiB safety limit.")
        }
        try FileManager.default.createDirectory(at: destinationDatabase.deletingLastPathComponent(), withIntermediateDirectories: true)
        try plaintext.write(to: destinationDatabase, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationDatabase.path)
    }

    private static func legacyKey(from passphrase: String) -> SymmetricKey {
        let digest = SHA256.hash(data: Data(passphrase.utf8))
        return SymmetricKey(data: Data(digest))
    }

    private static func derivedKey(from passphrase: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        guard salt.count == saltBytes, iterations == pbkdf2Iterations else {
            throw backupError(code: 6, message: "The encrypted backup uses unsupported key-derivation parameters.")
        }
        let password = Data(passphrase.utf8)
        var derived = Data(count: keyBytes)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        password.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyBytes
                    )
                }
            }
        }
        guard status == kCCSuccess else {
            throw backupError(code: 7, message: "Could not derive the encrypted-backup key.")
        }
        return SymmetricKey(data: derived)
    }

    private static func envelope(salt: Data, iterations: UInt32, sealedPayload: Data) -> Data {
        var data = Data()
        data.append(envelopeMagic)
        data.append(envelopeVersion)
        data.append(UInt8(salt.count))
        var bigEndianIterations = iterations.bigEndian
        withUnsafeBytes(of: &bigEndianIterations) { data.append(contentsOf: $0) }
        data.append(salt)
        data.append(sealedPayload)
        return data
    }

    private static func parseEnvelope(_ data: Data) throws -> (salt: Data, iterations: UInt32, sealedPayload: Data) {
        let bytes = [UInt8](data)
        let headerBytes = envelopeMagic.count + 1 + 1 + MemoryLayout<UInt32>.size
        guard bytes.count >= headerBytes + saltBytes + 28 else {
            throw backupError(code: 8, message: "The encrypted backup envelope is truncated.")
        }
        var cursor = envelopeMagic.count
        let version = bytes[cursor]
        cursor += 1
        guard version == envelopeVersion else {
            throw backupError(code: 9, message: "This encrypted backup format is not supported by this Blackbox version.")
        }
        let encodedSaltBytes = Int(bytes[cursor])
        cursor += 1
        guard encodedSaltBytes == saltBytes else {
            throw backupError(code: 10, message: "The encrypted backup contains an invalid salt.")
        }
        let iterations = bytes[cursor..<(cursor + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        cursor += 4
        guard iterations == pbkdf2Iterations else {
            throw backupError(code: 11, message: "The encrypted backup uses unsupported key-derivation parameters.")
        }
        let salt = Data(bytes[cursor..<(cursor + encodedSaltBytes)])
        cursor += encodedSaltBytes
        let sealedPayload = Data(bytes[cursor...])
        return (salt, iterations, sealedPayload)
    }

    private static func backupError(code: Int, message: String) -> NSError {
        NSError(domain: "BlackboxBackup", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func selfContainedPayload(from database: URL) throws -> Data {
        let prefix = try Data(contentsOf: database, options: [.mappedIfSafe]).prefix(16)
        guard String(data: prefix, encoding: .utf8) == "SQLite format 3\0" else {
            return try Data(contentsOf: database)
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Blackbox-Backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let snapshot = folder.appendingPathComponent("Snapshot.sqlite")
        let source = try SQLiteConnection(path: database.path, readOnly: true)
        try source.backup(to: snapshot.path)
        let verified = try SQLiteConnection(path: snapshot.path, readOnly: true)
        guard try verified.integrityCheck().lowercased() == "ok" else {
            throw NSError(domain: "BlackboxBackup", code: 5, userInfo: [NSLocalizedDescriptionKey: "The SQLite backup snapshot failed integrity verification."])
        }
        return try Data(contentsOf: snapshot)
    }

    private static func backupStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return "\(formatter.string(from: Date()))-\(UUID().uuidString)"
    }
}
