import Foundation
import UserNotifications

/// Local notifications for finished Scout runs. The "what's new" check is
/// shared between foreground refresh and the background task: every finished
/// (terminal) run ID we've already notified about — or seen at first launch —
/// is recorded so each run notifies at most once.
enum NotificationService {

    private static let seenKey = "notifiedRunIDs"
    private static let primedKey = "notifiedRunIDsPrimed"

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Compare current runs against the seen-set; notify for newly finished
    /// ones and update the set. On first run (unprimed), seed the set without
    /// notifying so installing the app doesn't replay history.
    static func processRuns(_ runs: [Run], settings: AppSettings, defaults: UserDefaults = .standard) async {
        let terminal = runs.filter { $0.status.isTerminal }
        var seen = Set(defaults.stringArray(forKey: seenKey) ?? [])
        let primed = defaults.bool(forKey: primedKey)

        if !primed {
            defaults.set(true, forKey: primedKey)
            defaults.set(Array(terminal.map(\.id)), forKey: seenKey)
            return
        }

        let fresh = terminal.filter { !seen.contains($0.id) }
        for run in fresh {
            seen.insert(run.id)
            guard settings.notifyOnRunFinished else { continue }
            let isBad = run.status == .failure || run.status == .timeout || run.status == .rateLimited
            if settings.notifyFailuresOnly && !isBad { continue }
            await fire(for: run)
        }
        // Cap the persisted set so it doesn't grow forever.
        let keep = terminal.suffix(500).map(\.id).filter(seen.contains)
        defaults.set(Array(Set(keep).union(fresh.map(\.id))), forKey: seenKey)
    }

    private static func fire(for run: Run) async {
        let content = UNMutableNotificationContent()
        content.title = "\(run.displayName) finished"
        switch run.status {
        case .success:
            var body = "Completed successfully"
            if let d = run.duration { body += " in \(Int(d / 60))m \(Int(d) % 60)s" }
            if let cost = run.cost, cost > 0 { body += " · $\(cost)" }
            content.body = body + "."
        case .failure:
            content.body = "Failed (exit code \(run.exitCode.map(String.init) ?? "?"))."
        case .timeout:
            content.body = "Timed out."
        case .rateLimited:
            content.body = "Hit a rate limit."
        case .skippedBudget:
            content.body = "Skipped — budget cap reached."
        case .skippedConcurrency:
            content.body = "Skipped — another session was running."
        default:
            content.body = run.status.displayName + "."
        }
        content.sound = .default
        content.threadIdentifier = "scout-runs"
        content.userInfo = ["runID": run.id]

        let request = UNNotificationRequest(
            identifier: "run-\(run.id)",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
