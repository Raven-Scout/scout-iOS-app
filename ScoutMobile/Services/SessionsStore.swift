import Foundation
import Combine

/// Loads recent runs from `.scout-logs/` and joins them with cost entries
/// from `usage-tracker.jsonl`.
@MainActor
final class SessionsStore: ObservableObject {

    @Published private(set) var runs: [Run] = []
    @Published private(set) var usageEntries: [UsageEntry] = []
    @Published private(set) var isLoading = false
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
            Task { @MainActor [weak self] in await self?.reload() }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        let vault = self.vault
        let result = await Task.detached { () -> (runs: [Run], usage: [UsageEntry], error: String?) in
            Self.loadAll(vault: vault)
        }.value
        runs = result.runs
        usageEntries = result.usage
        lastError = result.error
    }

    /// Read the full log text for a run's detail view.
    func logText(for run: Run) async -> String {
        let vault = self.vault
        let path = "\(Self.logsDir)/\(run.logPath.lastPathComponent)"
        return await Task.detached { () -> String in
            guard let data = vault.readFileIfExists(relativePath: path) else { return "(log unavailable)" }
            return String(data: data, encoding: .utf8) ?? "(log is not valid UTF-8)"
        }.value
    }

    nonisolated static let logsDir = ".scout-logs"

    nonisolated static func loadAll(vault: VaultAccess, now: Date = Date()) -> (runs: [Run], usage: [UsageEntry], error: String?) {
        let usage = loadUsage(vault: vault)
        do {
            let names = try vault.listDirectory(relativePath: logsDir)
            var out: [Run] = []
            for name in names where name.hasSuffix(".log") {
                let fileURL = URL(fileURLWithPath: "\(logsDir)/\(name)")
                guard let parsed = SessionLogParser.parseFilename(fileURL) else { continue }
                guard let data = vault.readFileIfExists(relativePath: "\(logsDir)/\(name)"),
                      let text = String(data: data, encoding: .utf8) else { continue }
                let body = SessionLogParser.parseBody(text: text, sizeBytes: Int64(data.count))
                let status = SessionLogParser.promoteOrphan(
                    parsedStatus: body.status,
                    startedAt: parsed.startedAt,
                    type: parsed.type,
                    now: now
                )
                let cost = matchCost(usage: usage, type: parsed.type, near: parsed.startedAt, endedAt: body.endedAt)
                out.append(Run(
                    id: Run.makeId(type: parsed.type, startedAt: parsed.startedAt),
                    type: parsed.type,
                    runnerScript: parsed.runnerScript,
                    startedAt: parsed.startedAt,
                    endedAt: body.endedAt,
                    status: status,
                    exitCode: body.exitCode,
                    durationSeconds: body.durationSeconds,
                    cost: cost?.budgetSpent,
                    budgetCap: cost?.budgetCap,
                    logPath: URL(fileURLWithPath: "\(logsDir)/\(name)"),
                    logSizeBytes: body.logSizeBytes,
                    errorsDetected: body.errorsDetected
                ))
            }
            out.sort { $0.startedAt > $1.startedAt }
            return (SessionLogParser.resolveStaleRunning(out), usage, nil)
        } catch VaultAccess.VaultError.fileNotFound {
            return ([], usage, nil)
        } catch {
            return ([], usage, error.localizedDescription)
        }
    }

    nonisolated static func loadUsage(vault: VaultAccess) -> [UsageEntry] {
        guard let data = vault.readFileIfExists(relativePath: "\(logsDir)/usage-tracker.jsonl"),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            line.data(using: .utf8).flatMap { UsageEntry.decode(jsonLine: $0) }
        }
    }

    /// Match a usage entry to a run. Entries are written at session end, so
    /// match near `endedAt` when available, else `startedAt`. The `type`
    /// field drifted from coarse keys ("briefing") to slot keys
    /// ("midday-consolidation"); accept either containing the coarse key.
    nonisolated static func matchCost(usage: [UsageEntry], type: RunType, near startedAt: Date, endedAt: Date?, tolerance: TimeInterval = 180) -> UsageEntry? {
        let key = type.costTrackerKey
        let candidates = usage.filter { entry in
            (entry.source ?? "session") != "schedule.tick"
                && (entry.type == key || entry.type.contains(key))
        }
        let anchors = [endedAt, startedAt].compactMap { $0 }
        for anchor in anchors {
            if let hit = candidates.first(where: { abs($0.ts.timeIntervalSince(anchor)) <= tolerance }) {
                return hit
            }
        }
        return nil
    }
}
