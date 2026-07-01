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
