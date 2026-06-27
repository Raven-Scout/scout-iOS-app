import Foundation
import Combine

/// Read-only view of `.scout-state/schedule.yaml` plus locally computed
/// upcoming fires. (Editing the schedule stays a desktop/scoutctl feature —
/// the YAML is rewritten atomically by scoutctl with header preservation,
/// which we don't replicate here.)
@MainActor
final class ScheduleStore: ObservableObject {

    @Published private(set) var slots: [Slot] = []
    @Published private(set) var upcoming: [UpcomingRun] = []
    @Published private(set) var lastError: String?

    private let vault: VaultAccess
    private var refreshTimer: Timer?

    init(vault: VaultAccess) {
        self.vault = vault
    }

    func start() {
        Task { await reload() }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recomputeUpcoming() }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func reload() async {
        let vault = self.vault
        let result = await vault.performIO { () -> Result<[Slot], Error> in
            do {
                let data = try vault.readFile(relativePath: ".scout-state/schedule.yaml")
                let text = String(data: data, encoding: .utf8) ?? ""
                return .success(ScheduleParser.parse(text: text))
            } catch {
                return .failure(error)
            }
        }
        switch result {
        case .success(let parsed):
            slots = parsed
            lastError = nil
        case .failure(let error):
            lastError = error.localizedDescription
        }
        recomputeUpcoming()
    }

    func recomputeUpcoming() {
        upcoming = UpcomingRunCalculator.upcoming(slots: slots, from: Date(), limit: 8)
    }
}
