import Foundation

public enum FolderAccessMode: String, Codable {
    case standard
    case securityScoped

    public static var forCurrentProcess: FolderAccessMode {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil ? .standard : .securityScoped
    }
}

public enum FolderBookmarkResolution: Equatable {
    case missing
    case stale
    case available(URL)
}

/// Persists user-selected folders without retaining broader filesystem access.
/// Direct-distribution builds use ordinary bookmarks; sandboxed builds opt in to
/// security-scoped bookmarks and access only for the duration of an operation.
public final class FolderAccessStore {
    public enum Purpose: String, CaseIterable, Codable {
        case exports
        case backups
    }

    private let defaults: UserDefaults
    private let keyPrefix: String
    public let mode: FolderAccessMode

    public init(
        defaults: UserDefaults = .standard,
        keyPrefix: String = "Blackbox.folderBookmark",
        mode: FolderAccessMode = .forCurrentProcess
    ) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
        self.mode = mode
    }

    public func remember(_ folder: URL, for purpose: Purpose) throws {
        let options: URL.BookmarkCreationOptions = mode == .securityScoped ? [.withSecurityScope] : [.minimalBookmark]
        let data = try folder.standardizedFileURL.bookmarkData(
            options: options,
            includingResourceValuesForKeys: [.isDirectoryKey],
            relativeTo: nil
        )
        defaults.set(data, forKey: key(for: purpose))
    }

    public func resolve(_ purpose: Purpose) -> FolderBookmarkResolution {
        guard let data = defaults.data(forKey: key(for: purpose)) else { return .missing }
        var stale = false
        do {
            let options: URL.BookmarkResolutionOptions = mode == .securityScoped ? [.withSecurityScope] : [.withoutUI]
            let url = try URL(
                resolvingBookmarkData: data,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            guard !stale else { return .stale }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else { return .stale }
            return .available(url.standardizedFileURL)
        } catch {
            return .stale
        }
    }

    public func forget(_ purpose: Purpose) {
        defaults.removeObject(forKey: key(for: purpose))
    }

    public func withAccess<T>(to folder: URL, _ work: () throws -> T) throws -> T {
        guard mode == .securityScoped else { return try work() }
        guard folder.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: folder.path])
        }
        defer { folder.stopAccessingSecurityScopedResource() }
        return try work()
    }

    private func key(for purpose: Purpose) -> String {
        "\(keyPrefix).\(purpose.rawValue)"
    }
}
