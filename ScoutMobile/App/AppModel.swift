import Foundation
import SwiftUI
import Combine

/// Root state container. Owns the vault handle and all feature stores —
/// the iOS counterpart of the desktop app's AppState.
@MainActor
final class AppModel: ObservableObject {

    let settings: AppSettings
    let vault: VaultAccess

    @Published private(set) var hasVault: Bool

    let actionItems: ActionItemsStore
    let sessions: SessionsStore
    let schedule: ScheduleStore
    let knowledge: KnowledgeBaseStore

    init() {
        let settings = AppSettings.shared
        let vault = VaultAccess()
        self.settings = settings
        self.vault = vault
        self.hasVault = VaultAccess.hasBookmark()
        self.actionItems = ActionItemsStore(vault: vault, settings: settings)
        self.sessions = SessionsStore(vault: vault)
        self.schedule = ScheduleStore(vault: vault)
        self.knowledge = KnowledgeBaseStore(vault: vault)
    }

    /// Called from the folder picker once the user grants access.
    func adoptVault(url: URL) throws {
        try VaultAccess.saveBookmark(for: url)
        hasVault = true
        startStores()
        Task {
            _ = await NotificationService.requestAuthorization()
            BackgroundRefresh.schedule()
        }
    }

    func clearVault() {
        VaultAccess.clearBookmark()
        hasVault = false
        actionItems.stop()
        sessions.stop()
        schedule.stop()
    }

    func handleForeground() {
        guard hasVault else { return }
        startStores()
        Task {
            await sessions.reload()
            await NotificationService.processRuns(sessions.runs, settings: settings)
        }
    }

    private var started = false
    func startStores() {
        guard hasVault else { return }
        if !started {
            started = true
            actionItems.start()
            sessions.start()
            schedule.start()
        } else {
            Task { await actionItems.reloadIfChanged() }
            Task { await schedule.reload() }
        }
    }
}
