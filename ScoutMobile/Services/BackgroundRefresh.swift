import Foundation
import BackgroundTasks

/// Periodic background check for newly finished Scout runs. Uses
/// BGAppRefreshTask — iOS decides the actual cadence (typically tens of
/// minutes when the app is used regularly).
enum BackgroundRefresh {
    static let taskIdentifier = "com.scout.mobile.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()   // always chain the next refresh

        let work = Task.detached {
            let vault = VaultAccess()
            guard VaultAccess.hasBookmark() else {
                task.setTaskCompleted(success: true)
                return
            }
            let runs = await vault.performIO { SessionsStore.loadAll(vault: vault).runs }
            let settings = await MainActor.run { AppSettings.shared }
            await NotificationService.processRuns(runs, settings: settings)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }
}
