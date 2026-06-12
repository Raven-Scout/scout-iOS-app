import Foundation

/// Access to the user-chosen Scout vault folder (typically inside the
/// Obsidian iCloud Drive container). Holds the security-scoped bookmark and
/// provides coordinated, download-aware reads and writes.
///
/// All file I/O goes through NSFileCoordinator so we play nice with the
/// iCloud daemon and the Obsidian app writing the same files.
final class VaultAccess: @unchecked Sendable {
    static let bookmarkKey = "vaultBookmark"

    enum VaultError: LocalizedError {
        case noBookmark
        case bookmarkResolutionFailed
        case fileNotFound(String)
        case notDownloadable(String)

        var errorDescription: String? {
            switch self {
            case .noBookmark: return "No Scout folder selected yet."
            case .bookmarkResolutionFailed: return "Could not re-open the Scout folder. Pick it again in Settings."
            case .fileNotFound(let p): return "File not found: \(p)"
            case .notDownloadable(let p): return "Could not download from iCloud: \(p)"
            }
        }
    }

    /// Persist a newly picked folder URL as a security-scoped bookmark.
    /// Call from the document-picker completion (the URL is security-scoped
    /// at that point).
    static func saveBookmark(for url: URL, defaults: UserDefaults = .standard) throws {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: bookmarkKey)
    }

    static func clearBookmark(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: bookmarkKey)
    }

    static func hasBookmark(defaults: UserDefaults = .standard) -> Bool {
        if overridePath != nil { return true }
        return defaults.data(forKey: bookmarkKey) != nil
    }

    /// DEBUG-only escape hatch: point the app at a vault by literal path
    /// (`SCOUT_VAULT_PATH` env var). Lets simulator runs and screenshots skip
    /// the document picker. Never active in release builds.
    static var overridePath: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["SCOUT_VAULT_PATH"]
        #else
        nil
        #endif
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Resolve the bookmark to a URL. The caller must wrap actual file access
    /// in `withVault { root in … }` so the security scope stays open.
    private func resolveRoot() throws -> URL {
        if let override = Self.overridePath {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        guard let data = defaults.data(forKey: Self.bookmarkKey) else {
            throw VaultError.noBookmark
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            throw VaultError.bookmarkResolutionFailed
        }
        if stale, let refreshed = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
            defaults.set(refreshed, forKey: Self.bookmarkKey)
        }
        return url
    }

    /// Run `body` with the vault root URL while holding the security scope.
    func withVault<T>(_ body: (URL) throws -> T) throws -> T {
        let root = try resolveRoot()
        let didStart = root.startAccessingSecurityScopedResource()
        defer { if didStart { root.stopAccessingSecurityScopedResource() } }
        return try body(root)
    }

    var displayPath: String {
        (try? resolveRoot().path) ?? ""
    }

    // MARK: - Reads

    /// Coordinated read of a file given its vault-relative path. Triggers an
    /// iCloud download when the item exists only as a placeholder and waits
    /// briefly for it to materialize.
    func readFile(relativePath: String) throws -> Data {
        try withVault { root in
            let url = root.appendingPathComponent(relativePath)
            return try Self.coordinatedRead(url)
        }
    }

    func readFileIfExists(relativePath: String) -> Data? {
        try? readFile(relativePath: relativePath)
    }

    /// List a directory inside the vault. Normalizes iCloud placeholder names
    /// (`.<name>.icloud`) back to their real file names so callers see one
    /// consistent namespace whether or not files are downloaded.
    func listDirectory(relativePath: String) throws -> [String] {
        try withVault { root in
            let dir = relativePath.isEmpty ? root : root.appendingPathComponent(relativePath)
            let entries = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            return entries.map(Self.normalizePlaceholderName).sorted()
        }
    }

    func fileExists(relativePath: String) -> Bool {
        (try? withVault { root in
            let url = root.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: url.path) { return true }
            return FileManager.default.fileExists(atPath: Self.placeholderURL(for: url).path)
        }) ?? false
    }

    /// Looks like a Scout vault? (used to validate the picked folder)
    func looksLikeScoutVault() -> Bool {
        fileExists(relativePath: "action-items") || fileExists(relativePath: "scout-config.yaml")
    }

    // MARK: - Writes

    /// Coordinated atomic write. Caller is responsible for read-modify-write
    /// hygiene (re-read inside the same coordination block when mutating).
    func writeFile(relativePath: String, data: Data) throws {
        try withVault { root in
            let url = root.appendingPathComponent(relativePath)
            var coordError: NSError?
            var writeError: Error?
            NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { actualURL in
                do {
                    try data.write(to: actualURL, options: .atomic)
                } catch {
                    writeError = error
                }
            }
            if let coordError { throw coordError }
            if let writeError { throw writeError }
        }
    }

    /// Coordinated read-modify-write of a text file. `transform` receives the
    /// current contents and returns the new contents (or nil to abort).
    func modifyTextFile(relativePath: String, transform: (String) throws -> String?) throws {
        try withVault { root in
            let url = root.appendingPathComponent(relativePath)
            try Self.ensureDownloaded(url)
            var coordError: NSError?
            var innerError: Error?
            NSFileCoordinator(filePresenter: nil).coordinate(
                readingItemAt: url, options: [],
                writingItemAt: url, options: .forMerging,
                error: &coordError
            ) { readURL, writeURL in
                do {
                    let text = try String(contentsOf: readURL, encoding: .utf8)
                    if let newText = try transform(text) {
                        try newText.data(using: .utf8)?.write(to: writeURL, options: .atomic)
                    }
                } catch {
                    innerError = error
                }
            }
            if let coordError { throw coordError }
            if let innerError { throw innerError }
        }
    }

    // MARK: - iCloud helpers

    static func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
    }

    static func normalizePlaceholderName(_ name: String) -> String {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return name }
        return String(name.dropFirst().dropLast(".icloud".count))
    }

    /// If `url` is an undownloaded iCloud item, request the download and wait
    /// (bounded) for it to appear.
    static func ensureDownloaded(_ url: URL, timeout: TimeInterval = 15) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return }
        let placeholder = placeholderURL(for: url)
        guard fm.fileExists(atPath: placeholder.path) else {
            throw VaultError.fileNotFound(url.lastPathComponent)
        }
        try fm.startDownloadingUbiquitousItem(at: url)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if fm.fileExists(atPath: url.path) { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw VaultError.notDownloadable(url.lastPathComponent)
    }

    static func coordinatedRead(_ url: URL) throws -> Data {
        try ensureDownloaded(url)
        var coordError: NSError?
        var data: Data?
        var readError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordError) { actualURL in
            do {
                data = try Data(contentsOf: actualURL)
            } catch {
                readError = error
            }
        }
        if let coordError { throw coordError }
        if let readError { throw readError }
        guard let data else { throw VaultError.fileNotFound(url.lastPathComponent) }
        return data
    }
}
