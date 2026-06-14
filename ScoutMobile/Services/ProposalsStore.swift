import Foundation
import Combine

/// Loads + watches `dreaming-proposals.md` and publishes the parsed proposals
/// plus a pending-count for the tab badge.
///
/// Mirrors `ActionItemsStore`: iOS has no FSEvents on security-scoped external
/// folders, so refresh is polling-based — on foreground, on demand
/// (pull-to-refresh), and a timer. The file lives at the vault root (the Scout
/// repo), so there is no per-date dimension.
@MainActor
final class ProposalsStore: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case missing
        case failed(String)
    }

    @Published private(set) var proposals: [Proposal] = []
    @Published private(set) var state: State = .idle

    /// Number of proposals still awaiting the user's decision — the value the
    /// tab badge shows.
    var pendingCount: Int { proposals.filter(\.isAwaitingDecision).count }

    let relativePath = "dreaming-proposals.md"

    private let vault: VaultAccess
    private var refreshTimer: Timer?
    private var lastBytes: Int?

    init(vault: VaultAccess) {
        self.vault = vault
    }

    func start() {
        Task { await reload() }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.reloadIfChanged() }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func reload() async {
        if case .idle = state { state = .loading }
        let path = relativePath
        let vault = self.vault
        let result: (state: State, proposals: [Proposal], bytes: Int?) = await Task.detached {
            Self.load(path: path, vault: vault)
        }.value
        state = result.state
        proposals = result.proposals
        lastBytes = result.bytes
    }

    /// Cheap polling reload — only reparse when the byte size changed.
    func reloadIfChanged() async {
        guard case .loaded = state, let currentBytes = lastBytes else {
            await reload()
            return
        }
        let path = relativePath
        let vault = self.vault
        let changed = await Task.detached { () -> Bool in
            guard let data = vault.readFileIfExists(relativePath: path) else { return true }
            return data.count != currentBytes
        }.value
        if changed { await reload() }
    }

    nonisolated private static func load(path: String, vault: VaultAccess) -> (State, [Proposal], Int?) {
        do {
            let data = try vault.readFile(relativePath: path)
            guard let text = String(data: data, encoding: .utf8) else {
                return (.failed("File is not valid UTF-8."), [], nil)
            }
            return (.loaded, ProposalsParser.parse(text: text), data.count)
        } catch VaultAccess.VaultError.fileNotFound {
            return (.missing, [], nil)
        } catch {
            return (.failed(error.localizedDescription), [], nil)
        }
    }

    // MARK: - Mutations

    /// Flip a proposal's status and re-read the file so the UI reflects it.
    func decide(_ decision: ProposalDecision, proposal: Proposal) async throws {
        let path = relativePath
        let vault = self.vault
        try await Task.detached {
            try ProposalsWriter.decide(decision, proposal: proposal, in: path, vault: vault)
        }.value
        await reload()
    }
}
