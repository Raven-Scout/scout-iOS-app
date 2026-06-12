import Foundation

/// Parses `.scout-logs/<runner>-YYYY-MM-DD_HH-MM.log` filenames and bodies
/// into `Run` values. Ported from the desktop app's SessionLogService
/// (static parsing layer only — the iOS app polls instead of FSEvents).
enum SessionLogParser {

    struct ParsedFilename: Equatable {
        let runnerScript: String
        let type: RunType
        let startedAt: Date
    }

    static func parseFilename(_ url: URL, timeZone: TimeZone = .current) -> ParsedFilename? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let underscoreIdx = name.firstIndex(of: "_") else { return nil }
        let head = String(name[..<underscoreIdx])                       // "scout-2026-04-19"
        let tail = String(name[name.index(after: underscoreIdx)...])    // "08-03"
        let headParts = head.components(separatedBy: "-")
        guard headParts.count == 4 else { return nil }
        let runner = headParts[0]
        guard ["scout", "dreaming", "research"].contains(runner) else { return nil }

        let tailParts = tail.components(separatedBy: "-")
        guard tailParts.count == 2 else { return nil }

        // Log filenames carry the producing machine's local wall-clock time.
        var components = DateComponents()
        components.year = Int(headParts[1])
        components.month = Int(headParts[2])
        components.day = Int(headParts[3])
        components.hour = Int(tailParts[0])
        components.minute = Int(tailParts[1])
        components.timeZone = timeZone
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        guard let date = cal.date(from: components) else { return nil }

        let runnerScript: String = {
            switch runner {
            case "dreaming": return "run-dreaming.sh"
            case "research": return "run-research.sh"
            default: return "run-scout.sh"
            }
        }()

        let type = deriveType(runner: runner, date: date, timeZone: timeZone)
        return ParsedFilename(runnerScript: runnerScript, type: type, startedAt: date)
    }

    static func deriveType(runner: String, date: Date, timeZone: TimeZone = .current) -> RunType {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let hour = cal.component(.hour, from: date)
        let weekday = cal.component(.weekday, from: date)   // 1=Sun … 7=Sat
        let isWeekend = (weekday == 1 || weekday == 7)

        switch runner {
        case "scout":
            if isWeekend {
                switch hour {
                case ..<10: return .weekendBriefing
                default:    return .consolidation
                }
            }
            switch hour {
            case ..<10: return .morningBriefing
            default:    return .consolidation
            }
        case "dreaming":
            return .dreaming
        case "research":
            return .research
        default:
            return .manual
        }
    }

    struct ParsedBody: Equatable {
        let endedAt: Date?
        let exitCode: Int?
        let durationSeconds: Int?
        let status: RunStatus
        let logSizeBytes: Int64
        let errorsDetected: [DetectedError]
    }

    static func parseBody(text: String, sizeBytes: Int64) -> ParsedBody {
        let range = NSRange(text.startIndex..., in: text)

        // Matches the runner's finish marker across historical casings
        // ("SCOUT" pre-2026-05, "Scout Dreaming" current).
        guard let finishRegex = try? NSRegularExpression(
            pattern: #"=== Scout(?: \w+)? run finished at (.+?) \(exit code: (-?\d+)(?:, duration: (\d+)s)?\) ==="#,
            options: [.caseInsensitive]
        ) else {
            return ParsedBody(endedAt: nil, exitCode: nil, durationSeconds: nil, status: .running, logSizeBytes: sizeBytes, errorsDetected: [])
        }
        var endedAt: Date? = nil
        var exitCode: Int? = nil
        var durationSeconds: Int? = nil
        if let match = finishRegex.firstMatch(in: text, range: range),
           let dateRange = Range(match.range(at: 1), in: text),
           let codeRange = Range(match.range(at: 2), in: text) {
            endedAt = parseScoutTimestamp(String(text[dateRange]))
            exitCode = Int(text[codeRange])
            if match.range(at: 3).location != NSNotFound, let r = Range(match.range(at: 3), in: text) {
                durationSeconds = Int(text[r])
            }
        }

        func contains(_ pattern: String) -> Bool {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
            return re.firstMatch(in: text, range: range) != nil
        }
        let hasTimeout = contains(#"=== TIMEOUT:"#)
        let hasConcurrencySkip = contains(#"=== Another SCOUT session running"#)
        let hasBudgetSkip = contains(#"=== Budget check: skipping this run ==="#)
        let hasRateLimit = contains(#"Rate limit detected"#)

        let status: RunStatus
        if hasTimeout || exitCode == 124 || exitCode == 137 {
            status = .timeout
        } else if hasBudgetSkip {
            status = .skippedBudget
        } else if hasConcurrencySkip {
            status = .skippedConcurrency
        } else if hasRateLimit {
            status = .rateLimited
        } else if exitCode == 0 {
            status = .success
        } else if exitCode != nil {
            status = .failure
        } else {
            status = .running   // fallback: no terminal markers, no exit code
        }

        return ParsedBody(
            endedAt: endedAt,
            exitCode: exitCode,
            durationSeconds: durationSeconds,
            status: status,
            logSizeBytes: sizeBytes,
            errorsDetected: scanErrors(in: text)
        )
    }

    /// Promote `.running` runs whose `startedAt` is older than the per-type
    /// `orphanAfter` threshold to `.orphaned`.
    static func promoteOrphan(parsedStatus: RunStatus, startedAt: Date, type: RunType, now: Date) -> RunStatus {
        guard parsedStatus == .running else { return parsedStatus }
        return now.timeIntervalSince(startedAt) > type.orphanAfter ? .orphaned : .running
    }

    /// Demote `.running` entries when a newer run of the same type has a
    /// terminal status.
    static func resolveStaleRunning(_ runs: [Run]) -> [Run] {
        var latestTerminal: [RunType: Date] = [:]
        for r in runs where r.status != .running {
            let prev = latestTerminal[r.type] ?? .distantPast
            if r.startedAt > prev { latestTerminal[r.type] = r.startedAt }
        }
        return runs.map { r -> Run in
            guard r.status == .running,
                  let newerTerminal = latestTerminal[r.type],
                  newerTerminal > r.startedAt
            else { return r }
            return r.with(status: .orphaned)
        }
    }

    static func scanErrors(in text: String) -> [DetectedError] {
        let patterns: [String] = [
            "429", "rate.?limit", "overloaded", "throttle", "too many requests",
            "insufficient_quota", "context_length_exceeded", "internal server error"
        ]
        var out: [DetectedError] = []
        let lines = text.components(separatedBy: "\n")
        for (idx, line) in lines.enumerated() {
            for pat in patterns {
                if line.range(of: pat, options: [.regularExpression, .caseInsensitive]) != nil {
                    out.append(DetectedError(line: idx + 1, pattern: pat, snippet: String(line.prefix(200))))
                    break
                }
            }
        }
        return out
    }

    /// Parse the `date`-style timestamp the runner writes in finish markers,
    /// e.g. "Sun Apr 19 15:00:01 EDT 2026" or "Fri Jun 12 13:17:49 CEST 2026".
    /// POSIX DateFormatter doesn't know European abbreviations (CEST/CET), so
    /// pre-substitute a known zone token with a UTC offset.
    static func parseScoutTimestamp(_ s: String) -> Date? {
        let zoneOffsets: [String: Int] = [
            "EDT": -4 * 3600, "EST": -5 * 3600,
            "CDT": -5 * 3600, "CST": -6 * 3600,
            "MDT": -6 * 3600, "MST": -7 * 3600,
            "PDT": -7 * 3600, "PST": -8 * 3600,
            "GMT": 0, "BST": 1 * 3600,
            "CET":  1 * 3600, "CEST": 2 * 3600,
            "EET":  2 * 3600, "EEST": 3 * 3600,
            "WET":  0,        "WEST": 1 * 3600,
            "UTC": 0, "Z": 0,
        ]
        for (abbr, seconds) in zoneOffsets {
            guard s.contains(" \(abbr) ") else { continue }
            let sign = seconds >= 0 ? "+" : "-"
            let absSeconds = abs(seconds)
            let offsetStr = String(format: "%@%02d%02d", sign, absSeconds / 3600, (absSeconds % 3600) / 60)
            let normalised = s.replacingOccurrences(of: " \(abbr) ", with: " \(offsetStr) ")
            for fmt in ["EEE MMM d HH:mm:ss Z yyyy", "EEE MMM  d HH:mm:ss Z yyyy"] {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = fmt
                if let d = f.date(from: normalised) { return d }
            }
        }
        for fmt in ["EEE MMM d HH:mm:ss zzz yyyy", "EEE MMM  d HH:mm:ss zzz yyyy"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}
