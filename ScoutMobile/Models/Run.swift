import Foundation

/// Run-type vocabulary for Scout sessions. Mirrors the desktop app's
/// `RunType` — slot keys like `morning-consolidation` and
/// `evening-consolidation` both map to `.consolidation`.
enum RunType: String, CaseIterable, Codable, Sendable {
    case morningBriefing
    case weekendBriefing
    case consolidation
    case dreaming
    case research
    case manual

    var displayName: String {
        switch self {
        case .morningBriefing: return "Morning briefing"
        case .weekendBriefing: return "Weekend briefing"
        case .consolidation:   return "Consolidation"
        case .dreaming:        return "Dreaming"
        case .research:        return "Research"
        case .manual:          return "Manual run"
        }
    }

    /// The `type` string used in usage-tracker.jsonl (coarse-grained).
    /// Newer runners emit slot keys (`midday-consolidation`); cost matching
    /// checks both exact equality and suffix/contains against this key.
    var costTrackerKey: String {
        switch self {
        case .morningBriefing, .weekendBriefing: return "briefing"
        case .consolidation: return "consolidation"
        case .dreaming:      return "dreaming"
        case .research:      return "research"
        case .manual:        return "manual"
        }
    }

    /// How long after `startedAt` a run with no terminal marker should be
    /// promoted from `.running` to `.orphaned`.
    var orphanAfter: TimeInterval {
        switch self {
        case .morningBriefing, .weekendBriefing: return 30 * 60
        case .consolidation: return 20 * 60
        case .dreaming:      return 2 * 3600
        case .research:      return 2 * 3600
        case .manual:        return 45 * 60
        }
    }
}

/// Run outcome classification.
enum RunStatus: String, Codable, Sendable {
    case scheduled
    case running
    case success
    case failure
    case timeout
    case orphaned
    case skippedBudget
    case skippedConcurrency
    case rateLimited

    var displayName: String {
        switch self {
        case .scheduled:          return "Scheduled"
        case .running:            return "Running"
        case .success:            return "Success"
        case .failure:            return "Failed"
        case .timeout:            return "Timed out"
        case .orphaned:           return "Orphaned"
        case .skippedBudget:      return "Skipped (budget)"
        case .skippedConcurrency: return "Skipped (busy)"
        case .rateLimited:        return "Rate limited"
        }
    }

    /// Terminal = the run will not change state anymore.
    var isTerminal: Bool { self != .running && self != .scheduled }
}

struct DetectedError: Equatable, Hashable, Sendable {
    let line: Int
    let pattern: String
    let snippet: String
}

struct Run: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let type: RunType
    let runnerScript: String
    let startedAt: Date
    let endedAt: Date?
    let status: RunStatus
    let exitCode: Int?
    let durationSeconds: Int?
    let cost: Decimal?
    let budgetCap: Decimal?
    let logPath: URL
    let logSizeBytes: Int64
    let errorsDetected: [DetectedError]

    static func makeId(type: RunType, startedAt: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return "\(type.rawValue)-\(iso.string(from: startedAt))"
    }

    var displayName: String {
        if type != .manual { return type.displayName }
        switch runnerScript {
        case "run-dreaming.sh": return "Dreaming (manual)"
        case "run-research.sh": return "Research (manual)"
        default:                return "Briefing (manual)"
        }
    }

    var duration: TimeInterval? {
        if let durationSeconds { return TimeInterval(durationSeconds) }
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    func with(status: RunStatus) -> Run {
        Run(
            id: id, type: type, runnerScript: runnerScript,
            startedAt: startedAt, endedAt: endedAt, status: status,
            exitCode: exitCode, durationSeconds: durationSeconds,
            cost: cost, budgetCap: budgetCap,
            logPath: logPath, logSizeBytes: logSizeBytes,
            errorsDetected: errorsDetected
        )
    }
}
