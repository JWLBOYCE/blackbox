import Foundation

public struct LogbookPaths: Equatable {
    public var backupFolder: URL
    public var sourceLogTenDatabase: URL
    public var workingDatabase: URL

    public init(backupFolder: URL, sourceLogTenDatabase: URL, workingDatabase: URL) {
        self.backupFolder = backupFolder
        self.sourceLogTenDatabase = sourceLogTenDatabase
        self.workingDatabase = workingDatabase
    }

    public static var applicationSupport: LogbookPaths {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Blackbox", isDirectory: true)
        return LogbookPaths(
            backupFolder: root.appendingPathComponent("Backups", isDirectory: true),
            sourceLogTenDatabase: root
                .appendingPathComponent("Import Sources", isDirectory: true)
                .appendingPathComponent("LogTenCoreDataStore.sql"),
            workingDatabase: root.appendingPathComponent("Blackbox.sqlite")
        )
    }

    public static var desktopBackup: LogbookPaths {
        let folder = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
            .appendingPathComponent("LogTenPro_Backup_2026-06-21_101737", isDirectory: true)
        return LogbookPaths(
            backupFolder: folder,
            sourceLogTenDatabase: folder
                .appendingPathComponent("LogTenProData", isDirectory: true)
                .appendingPathComponent("LogTenCoreDataStore.sql"),
            workingDatabase: folder.appendingPathComponent("OpenPilotLogbook.sqlite")
        )
    }
}
