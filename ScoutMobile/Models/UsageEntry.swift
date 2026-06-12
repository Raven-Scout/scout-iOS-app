import Foundation

/// One line of `.scout-logs/usage-tracker.jsonl`. Field names drifted across
/// plugin versions (`ts_et` → `ts_local`; coarse types → slot keys), so the
/// decoder accepts both generations.
struct UsageEntry: Equatable, Sendable {
    let ts: Date
    let tsLocal: String
    let type: String
    let budgetCap: Decimal?
    let budgetSpent: Decimal?
    let exitCode: Int?
    let source: String?     // "session" | "runner" | "schedule.tick" | nil

    static func decode(jsonLine: Data) -> UsageEntry? {
        guard let obj = try? JSONSerialization.jsonObject(with: jsonLine) as? [String: Any] else { return nil }
        guard let tsString = obj["ts"] as? String, let ts = Self.parseISO(tsString) else { return nil }
        guard let type = obj["type"] as? String else { return nil }
        return UsageEntry(
            ts: ts,
            tsLocal: (obj["ts_local"] as? String) ?? (obj["ts_et"] as? String) ?? "",
            type: type,
            budgetCap: Self.decimal(obj["budget_cap"]),
            budgetSpent: Self.decimal(obj["budget_spent"]),
            exitCode: obj["exit_code"] as? Int,
            source: obj["source"] as? String
        )
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        if let n = value as? NSNumber { return n.decimalValue }
        if let s = value as? String { return Decimal(string: s) }
        return nil
    }

    private static func parseISO(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
