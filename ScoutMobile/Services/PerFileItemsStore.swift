import Foundation
import Combine

/// Loads + watches a per-file items directory (`docs/wishlist` or
/// `knowledge-base/research-queue`) and publishes the parsed items plus an
/// active-count for the tab badge.
///
/// iOS has no FSEvents on security-scoped external folders, so refresh is
/// polling-based: on `start()`, on foreground, on demand (pull-to-refresh),
/// and a 30 s timer — mirroring `ProposalsStore`. Each `*.md` file is one item;
/// files without frontmatter (index/readme files) parse to nil and are skipped.
@MainActor
final class PerFileItemsStore: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case missing          // the items directory does not exist (un-migrated vault)
        case failed(String)
    }

    @Published private(set) var items: [PerFileItem] = []
    @Published private(set) var state: State = .idle

    /// Number of items still active (open/in-progress) — feeds the tab badge.
    var activeCount: Int { items.filter(\.isActive).count }

    let config: PerFileTabConfig

    private let vault: VaultAccess
    private var refreshTimer: Timer?

    init(vault: VaultAccess, config: PerFileTabConfig) {
        self.vault = vault
        self.config = config
    }

    func start() {
        Task { await reload() }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.reload() }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func reload() async {
        if case .idle = state { state = .loading }
        let directory = config.directory
        let vault = self.vault
        let result: (state: State, items: [PerFileItem]) = await Task.detached {
            Self.load(directory: directory, vault: vault)
        }.value
        state = result.state
        // Avoid redundant publishes (the 30 s tick reparses every time).
        if result.items != items { items = result.items }
    }

    nonisolated private static func load(directory: String, vault: VaultAccess) -> (state: State, items: [PerFileItem]) {
        guard vault.fileExists(relativePath: directory) else { return (.missing, []) }
        let names: [String]
        do {
            names = try vault.listDirectory(relativePath: directory)
        } catch {
            return (.failed(error.localizedDescription), [])
        }
        let items = names
            .filter { $0.hasSuffix(".md") }
            // Newest-first: filenames are `YYYY-MM-DD-slug.md`, so reverse
            // lexicographic order is reverse-chronological.
            .sorted(by: >)
            .compactMap { name -> PerFileItem? in
                let rel = directory.isEmpty ? name : "\(directory)/\(name)"
                guard let data = vault.readFileIfExists(relativePath: rel),
                      let text = String(data: data, encoding: .utf8) else { return nil }
                return PerFileItemParser.parseFile(contents: text, relativePath: rel)
            }
        return (.loaded, items)
    }

    // MARK: - Mutations

    func addItem(title: String, priority: ItemPriority, body: String, optional: String?) async throws {
        let config = self.config
        let vault = self.vault
        try await Task.detached {
            _ = try PerFileItemsWriter.addItem(config: config, title: title, priority: priority,
                                               body: body, optional: optional, vault: vault)
        }.value
        await reload()
    }

    func resolve(_ resolution: ItemResolution, item: PerFileItem) async throws {
        let vault = self.vault
        try await Task.detached {
            try PerFileItemsWriter.resolve(resolution, item: item, vault: vault)
        }.value
        await reload()
    }
}
