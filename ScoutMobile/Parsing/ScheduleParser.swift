import Foundation

/// Minimal YAML-subset parser for `.scout-state/schedule.yaml`. The file has
/// a fixed two-level shape (`slots:` → slot key → scalar fields + one inline
/// list), so a full YAML library isn't needed. Unknown keys are ignored;
/// malformed slots are skipped rather than failing the whole file.
enum ScheduleParser {

    static func parse(text: String) -> [Slot] {
        var slots: [Slot] = []
        var inSlots = false
        var currentKey: String? = nil
        var fields: [String: String] = [:]

        func flush() {
            if let key = currentKey, let slot = buildSlot(key: key, fields: fields) {
                slots.append(slot)
            }
            currentKey = nil
            fields = [:]
        }

        for rawLine in text.components(separatedBy: "\n") {
            let noComment = stripComment(rawLine)
            let trimmed = noComment.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let indent = noComment.prefix(while: { $0 == " " }).count

            if indent == 0 {
                flush()
                inSlots = trimmed == "slots:"
                continue
            }
            guard inSlots else { continue }

            if indent == 2, trimmed.hasSuffix(":"), !trimmed.contains(" ") {
                flush()
                currentKey = String(trimmed.dropLast())
                continue
            }
            if indent >= 4, currentKey != nil, let colonIdx = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                fields[key] = value
            }
        }
        flush()
        return slots
    }

    private static func stripComment(_ line: String) -> String {
        // Strip `#` comments, but not inside quoted strings ("08:03" has no #
        // so a simple scan with quote tracking suffices).
        var out = ""
        var inQuote = false
        for ch in line {
            if ch == "\"" { inQuote.toggle() }
            if ch == "#" && !inQuote { break }
            out.append(ch)
        }
        return out
    }

    private static func buildSlot(key: String, fields: [String: String]) -> Slot? {
        guard let typeRaw = fields["type"], let type = SlotType(rawValue: typeRaw) else { return nil }
        guard let firesAt = fields["fires_at_local"].map(unquote), !firesAt.isEmpty else { return nil }
        let weekdays = fields["weekdays"].map(parseInlineList) ?? []
        let onMiss = fields["on_miss"].flatMap { OnMissPolicy(rawValue: $0) } ?? .skip
        return Slot(
            key: key,
            type: type,
            runner: fields["runner"].map(unquote) ?? "",
            firesAtLocal: firesAt,
            weekdays: weekdays,
            missedWindowHours: fields["missed_window_hours"].flatMap { Int($0) } ?? 0,
            onMiss: onMiss,
            cooldownMinutes: fields["cooldown_minutes"].flatMap { Int($0) } ?? 0,
            budgetUsd: fields["budget_usd"].flatMap { Double($0) },
            tz: fields["tz"].map(unquote)
        )
    }

    private static func unquote(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespaces)
        if out.hasPrefix("\"") && out.hasSuffix("\"") && out.count >= 2 {
            out = String(out.dropFirst().dropLast())
        }
        if out.hasPrefix("'") && out.hasSuffix("'") && out.count >= 2 {
            out = String(out.dropFirst().dropLast())
        }
        return out
    }

    private static func parseInlineList(_ s: String) -> [String] {
        var inner = s.trimmingCharacters(in: .whitespaces)
        guard inner.hasPrefix("[") && inner.hasSuffix("]") else { return [] }
        inner = String(inner.dropFirst().dropLast())
        return inner.components(separatedBy: ",")
            .map { unquote($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }
}

/// Computes upcoming fire times from parsed slots — the iOS stand-in for
/// `scoutctl schedule list-upcoming`.
enum UpcomingRunCalculator {

    /// Next `limit` fires across all slots, soonest first. Each slot's
    /// `fires_at_local` is interpreted in `slot.tz` when present, else the
    /// device's current timezone.
    static func upcoming(slots: [Slot], from now: Date = Date(), limit: Int = 10) -> [UpcomingRun] {
        var fires: [UpcomingRun] = []
        let iso = ISO8601DateFormatter()
        for slot in slots {
            guard let hm = slot.fireHourMinute else { continue }
            let weekdaySet = slot.calendarWeekdays
            guard !weekdaySet.isEmpty else { continue }
            var cal = Calendar(identifier: .gregorian)
            if let tzName = slot.tz, let tz = TimeZone(identifier: tzName) {
                cal.timeZone = tz
            }
            // Scan the next 8 days for matching weekday fires in the future.
            for dayOffset in 0...8 {
                guard let day = cal.date(byAdding: .day, value: dayOffset, to: now),
                      weekdaySet.contains(cal.component(.weekday, from: day)),
                      let fire = cal.date(bySettingHour: hm.hour, minute: hm.minute, second: 0, of: day),
                      fire > now else { continue }
                fires.append(UpcomingRun(
                    id: "\(slot.key)-\(iso.string(from: fire))",
                    slotKey: slot.key,
                    type: slot.type,
                    scheduledAt: fire
                ))
            }
        }
        return Array(fires.sorted { $0.scheduledAt < $1.scheduledAt }.prefix(limit))
    }
}
