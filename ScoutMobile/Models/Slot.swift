import Foundation

/// Swift mirror of the engine's Slot dataclass, parsed directly from the
/// vault's `.scout-state/schedule.yaml` (the iOS app has no scoutctl).
struct Slot: Identifiable, Equatable, Hashable, Sendable {
    let key: String
    let type: SlotType
    let runner: String
    /// "HH:MM" local wall-clock fire time.
    let firesAtLocal: String
    /// Weekday abbreviations: Mon, Tue, Wed, Thu, Fri, Sat, Sun.
    let weekdays: [String]
    let missedWindowHours: Int
    let onMiss: OnMissPolicy
    let cooldownMinutes: Int
    let budgetUsd: Double?
    let tz: String?

    var id: String { key }

    /// Weekday numbers in Calendar convention (1 = Sunday … 7 = Saturday).
    var calendarWeekdays: Set<Int> {
        let map = ["Sun": 1, "Mon": 2, "Tue": 3, "Wed": 4, "Thu": 5, "Fri": 6, "Sat": 7]
        return Set(weekdays.compactMap { map[$0] })
    }

    var fireHourMinute: (hour: Int, minute: Int)? {
        let parts = firesAtLocal.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return (h, m)
    }
}

enum SlotType: String, CaseIterable, Codable, Sendable {
    case briefing
    case consolidation
    case dreaming
    case research
    case manual

    var displayName: String { rawValue.capitalized }
}

enum OnMissPolicy: String, CaseIterable, Codable, Sendable {
    case fire
    case skip
    case collapse
}

/// A scheduled fire that hasn't happened yet, computed locally from the
/// parsed schedule (the desktop app gets these from scoutctl).
struct UpcomingRun: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let slotKey: String
    let type: SlotType
    let scheduledAt: Date
}
