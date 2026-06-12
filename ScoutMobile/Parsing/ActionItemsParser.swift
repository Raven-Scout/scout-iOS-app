import Foundation

/// Markdown parser for daily `action-items-YYYY-MM-DD.md` files.
/// Ported from the desktop app (Scout/ActionItems/ActionItemsParser.swift);
/// the line-level functions are the cross-platform parser contract asserted
/// by `parser-corpus.json` and MUST stay byte-compatible.
enum ActionItemsParser {

    /// Strip markdown tokens from a subject so it matches the Python CLIs'
    /// `_strip_markdown_tokens` output byte-for-byte. Token order matters.
    static func plainSubject(_ raw: String) -> String {
        var s = raw
        s = replaceRegex(in: s, pattern: #"~~(.+?)~~"#, template: "$1")
        s = replaceRegex(in: s, pattern: #"\*\*(.+?)\*\*"#, template: "$1")
        s = replaceRegex(in: s, pattern: #"`([^`]+)`"#, template: "$1")
        s = replaceRegex(in: s, pattern: #"\[\[([^\]|]+?)(?:\|[^\]]+)?\]\]"#, template: "$1")
        s = replaceRegex(in: s, pattern: #"\[([^\]]+)\]\([^)]+\)"#, template: "$1")
        return s
    }

    private static func replaceRegex(in s: String, pattern: String, template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: template)
    }

    /// Extract a leading `[#TAG] ` short-prefix marker: 2–8 chars of
    /// `[A-Z0-9]` with at least one letter. Pure-numeric refs like `[#555]`
    /// are GitHub issue refs, not tags. Returns `(nil, raw)` on absence.
    static func extractShortPrefix(_ raw: String) -> (prefix: String?, rest: String) {
        guard let re = try? NSRegularExpression(
            pattern: #"^\[#(?=[A-Z0-9]{2,8}\])([A-Z0-9]*[A-Z][A-Z0-9]*)\]\s*"#
        ) else { return (nil, raw) }
        let range = NSRange(raw.startIndex..., in: raw)
        guard let m = re.firstMatch(in: raw, range: range),
              let prefixRange = Range(m.range(at: 1), in: raw),
              let fullRange = Range(m.range, in: raw) else {
            return (nil, raw)
        }
        return (String(raw[prefixRange]), String(raw[fullRange.upperBound...]))
    }

    /// Scan `text` for Linear IDs, GitHub PR URLs, and Slack thread URLs.
    /// Emits them in first-match order with duplicates removed.
    static func detectDeepLinks(in text: String) -> [TaskDeepLink] {
        struct Hit { let range: Range<String.Index>; let link: TaskDeepLink }
        var hits: [Hit] = []

        func scan(_ pattern: String, _ make: (NSTextCheckingResult, String) -> TaskDeepLink?) {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return }
            let full = NSRange(text.startIndex..., in: text)
            re.enumerateMatches(in: text, range: full) { match, _, _ in
                guard let match, let range = Range(match.range, in: text) else { return }
                if let link = make(match, text) {
                    hits.append(Hit(range: range, link: link))
                }
            }
        }

        scan(#"\b[A-Z]{2,10}-\d+\b"#) { m, t in
            guard let r = Range(m.range, in: t) else { return nil }
            return .linear(id: String(t[r]))
        }
        scan(#"https://github\.com/([\w.\-]+)/([\w.\-]+)/pull/(\d+)"#) { m, t in
            guard let full = Range(m.range, in: t),
                  let r1 = Range(m.range(at: 1), in: t),
                  let r2 = Range(m.range(at: 2), in: t),
                  let r3 = Range(m.range(at: 3), in: t),
                  let n = Int(t[r3]),
                  let url = URL(string: String(t[full])) else { return nil }
            return .githubPR(repo: "\(t[r1])/\(t[r2])", number: n, rawURL: url)
        }
        scan(#"https://[\w.\-]+\.slack\.com/archives/[A-Z0-9]+/p\d+(?:\?[^\s)\"']+)?"#) { m, t in
            guard let r = Range(m.range, in: t), let url = URL(string: String(t[r])) else { return nil }
            return .slackThread(url)
        }

        hits.sort { $0.range.lowerBound < $1.range.lowerBound }

        var seen: Set<String> = []
        var result: [TaskDeepLink] = []
        for h in hits where seen.insert(h.link.id).inserted {
            result.append(h.link)
        }
        return result
    }

    enum ParseError: Error {
        case invalidDateInFilename
    }

    static func parse(text: String, sourceURL: URL, sourceBytes: Int, authorName: String = "user") throws -> ActionItemsDocument {
        let lines = text.components(separatedBy: "\n")

        // --- title + preamble ---
        var title = ""
        var preamble: [String] = []
        var i = 0
        while i < lines.count {
            let l = lines[i]
            if l.hasPrefix("# ") && title.isEmpty {
                title = String(l.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                i += 1
                break
            }
            i += 1
        }
        while i < lines.count {
            let l = lines[i]
            if l.hasPrefix("## ") { break }
            let trimmed = l.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed.isEmpty { i += 1; continue }
            preamble.append(trimmed)
            i += 1
        }

        // --- date from filename ---
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let dateString = stem.replacingOccurrences(of: "action-items-", with: "")
        guard let date = Self.dayFormatter.date(from: dateString) else {
            throw ParseError.invalidDateInFilename
        }

        // --- sections ---
        var sections: [ActionSection] = []
        var currentTasks: [ActionTask] = []
        var currentBullets: [String] = []
        var currentTables: [ActionSection.Table] = []
        var currentSubheads: [String] = []
        var currentEmoji = ""
        var currentTitle = ""
        var currentKind: ActionSection.Kind = .neutral
        var inSection = false

        var pendingTableHeaders: [String]? = nil
        var pendingTableRows: [[String]] = []

        func flushTable() {
            if let headers = pendingTableHeaders {
                currentTables.append(.init(headers: headers, rows: pendingTableRows))
            }
            pendingTableHeaders = nil
            pendingTableRows = []
        }

        func flushSection() {
            flushTable()
            if inSection {
                sections.append(ActionSection(
                    id: UUID(),
                    emoji: currentEmoji,
                    title: currentTitle,
                    kind: currentKind,
                    tasks: currentTasks,
                    bullets: currentBullets,
                    tables: currentTables,
                    subheads: currentSubheads
                ))
            }
            currentTasks = []
            currentBullets = []
            currentTables = []
            currentSubheads = []
            currentEmoji = ""
            currentTitle = ""
            currentKind = .neutral
        }

        let taskRe = try NSRegularExpression(pattern: #"^(\s*)- \[([ xX])\] (.+?)\s*$"#)
        let commentRe = try NSRegularExpression(pattern: #"^(\s+)>\s+([A-Za-z][A-Za-z0-9._-]*)(?:\s+\(([^)]+)\))?\s*:\s*(.+?)\s*$"#)
        let subBulletCommentRe = try NSRegularExpression(pattern: #"^(\s+)-\s+([A-Za-z][A-Za-z0-9._-]*)\s*:\s*(.+?)\s*$"#)
        let snoozeSubBulletRe = try NSRegularExpression(
            pattern: #"^\s+-\s+snoozed-until:\s*(\d{4}-\d{2}-\d{2})(?:\s*\(from-kind:\s*([A-Za-z]+)\))?\s*$"#
        )
        let carryInFromKindRe = try NSRegularExpression(
            pattern: #"_\(carried in from \d{4}-\d{2}-\d{2}(?:[^)]*?,\s*was\s+([A-Za-z]+))?\)_"#
        )
        let inlineCommentRe = try NSRegularExpression(pattern: #"^(\s+)(?:[-*+]\s+)?//==<<\s*(.+?)\s*>>==//\s*$"#)
        let bulletRe = try NSRegularExpression(pattern: #"^\s*-\s+(.+?)\s*$"#)
        let sectionRe = try NSRegularExpression(pattern: #"^## (\S+?)\s+(.+?)\s*$"#)
        let snoozeSuffixRe = try NSRegularExpression(pattern: #"\s*(?:—|–|-)\s*🛌 Snoozed until (\d{4}-\d{2}-\d{2})$"#)
        let carryInRe = try NSRegularExpression(pattern: #"_\(carried in from (\d{4}-\d{2}-\d{2})\)_"#)

        while i < lines.count {
            let line = lines[i]
            let stripped = line.trimmingCharacters(in: .whitespaces)

            if stripped == "---" || stripped == "***" {
                flushTable()
                i += 1; continue
            }

            // Section header
            if line.hasPrefix("## ") {
                flushSection()
                let nsLine = line as NSString
                let range = NSRange(location: 0, length: nsLine.length)
                if let m = sectionRe.firstMatch(in: line, range: range) {
                    let emoji = nsLine.substring(with: m.range(at: 1))
                    let rest  = nsLine.substring(with: m.range(at: 2))
                    let trimmedRest = rest.replacingOccurrences(of: #"\s*\(.*?\)\s*$"#, with: "", options: .regularExpression)
                    if isRecognizedEmoji(emoji) {
                        currentEmoji = emoji
                        currentTitle = trimmedRest
                    } else {
                        currentEmoji = ""
                        currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    }
                } else {
                    currentEmoji = ""
                    currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                currentKind = kindFor(emoji: currentEmoji, title: currentTitle)
                inSection = true
                i += 1; continue
            }

            // Subhead
            if line.hasPrefix("### ") && inSection {
                flushTable()
                currentSubheads.append(String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces))
                i += 1; continue
            }

            // Pipe-table row
            if stripped.hasPrefix("|") && stripped.hasSuffix("|") {
                let inner = String(stripped.dropFirst().dropLast())
                let cells = inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                let sepRe = try! NSRegularExpression(pattern: #"^:?-+:?$"#)
                let allSep = cells.allSatisfy { c in
                    let r = NSRange(location: 0, length: (c as NSString).length)
                    return sepRe.firstMatch(in: c, range: r) != nil
                }
                if allSep { i += 1; continue }
                if pendingTableHeaders == nil {
                    pendingTableHeaders = cells
                } else {
                    pendingTableRows.append(cells)
                }
                i += 1; continue
            } else {
                flushTable()
            }

            // Task line
            if inSection,
               let m = taskRe.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let nsLine = line as NSString
                let indent = nsLine.substring(with: m.range(at: 1))
                let mark = nsLine.substring(with: m.range(at: 2))
                let rest = nsLine.substring(with: m.range(at: 3))
                let done = mark.lowercased() == "x"
                let (shortPrefix, restWithoutPrefix) = extractShortPrefix(rest)
                let (subject, body) = splitSubjectBody(restWithoutPrefix)
                let plainSubj = plainSubject(subject)
                let deepLinks = detectDeepLinks(in: rest)
                var snoozedUntil: Date? = nil
                if let sm = snoozeSuffixRe.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length)),
                   let r = Range(sm.range(at: 1), in: body) {
                    snoozedUntil = Self.dayFormatter.date(from: String(body[r]))
                }
                var carriedInFrom: Date? = nil
                var carryInKind: ActionSection.Kind? = nil
                if let cm = carryInRe.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length)),
                   let r = Range(cm.range(at: 1), in: body) {
                    carriedInFrom = Self.dayFormatter.date(from: String(body[r]))
                }
                if let cm = carryInFromKindRe.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length)),
                   cm.range(at: 1).location != NSNotFound,
                   let r = Range(cm.range(at: 1), in: body) {
                    carryInKind = ActionSection.Kind(rawValue: String(body[r]).lowercased())
                }
                currentTasks.append(ActionTask(
                    id: UUID(),
                    lineNumber: i + 1,
                    done: done,
                    subject: subject,
                    plainSubject: plainSubj,
                    body: body,
                    comments: [],
                    deepLinks: deepLinks,
                    snoozedUntil: snoozedUntil,
                    carriedInFrom: carriedInFrom,
                    indentLevel: indentLevelFor(indent),
                    shortPrefix: shortPrefix,
                    snoozedFromKind: carryInKind
                ))
                i += 1; continue
            }

            // Blockquote comment attached to the last task
            if inSection,
               let last = currentTasks.last,
               let cm = commentRe.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let nsLine = line as NSString
                let author = nsLine.substring(with: cm.range(at: 2))
                let ts = cm.range(at: 3).location != NSNotFound ? nsLine.substring(with: cm.range(at: 3)) : ""
                let body = nsLine.substring(with: cm.range(at: 4))
                currentTasks[currentTasks.count - 1] = last.with(
                    comments: last.comments + [TaskComment(author: author, timestamp: ts, text: body)]
                )
                i += 1; continue
            }

            // Sub-bullet snooze marker — consume before subBulletCommentRe
            // would expose it as a comment from author "snoozed-until".
            if inSection,
               let last = currentTasks.last,
               let sm = snoozeSubBulletRe.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let nsLine = line as NSString
                let dateStr = nsLine.substring(with: sm.range(at: 1))
                let parsedDate = Self.dayFormatter.date(from: dateStr)
                var parsedKind: ActionSection.Kind? = nil
                if sm.range(at: 2).location != NSNotFound {
                    parsedKind = ActionSection.Kind(rawValue: nsLine.substring(with: sm.range(at: 2)).lowercased())
                }
                currentTasks[currentTasks.count - 1] = last.with(
                    snoozedUntil: .some(parsedDate ?? last.snoozedUntil),
                    snoozedFromKind: .some(parsedKind ?? last.snoozedFromKind)
                )
                i += 1; continue
            }

            // Sub-bullet comment: `  - <author>: <text>` (scoutctl ≥ v0.4).
            if inSection,
               let last = currentTasks.last,
               let cm = subBulletCommentRe.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let nsLine = line as NSString
                let author = nsLine.substring(with: cm.range(at: 2))
                let body = nsLine.substring(with: cm.range(at: 3))
                currentTasks[currentTasks.count - 1] = last.with(
                    comments: last.comments + [TaskComment(author: author, timestamp: "", text: body)]
                )
                i += 1; continue
            }

            // Obsidian inline-comment style: `//==<< text >>==//`
            if inSection,
               let last = currentTasks.last,
               let im = inlineCommentRe.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let body = (line as NSString).substring(with: im.range(at: 2))
                currentTasks[currentTasks.count - 1] = last.with(
                    comments: last.comments + [TaskComment(author: authorName, timestamp: "", text: body)]
                )
                i += 1; continue
            }

            // Bullet (section-level)
            if inSection,
               let bm = bulletRe.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let rest = (line as NSString).substring(with: bm.range(at: 1))
                currentBullets.append(rest)
                i += 1; continue
            }

            // Paragraph in a section
            if inSection && !stripped.isEmpty {
                currentBullets.append(stripped)
            }
            i += 1
        }
        flushSection()

        return ActionItemsDocument(
            date: date,
            title: title,
            preamble: preamble,
            sections: sections,
            sourceURL: sourceURL,
            sourceBytes: sourceBytes
        )
    }

    // --- helpers ---

    /// yyyy-MM-dd in the device's local timezone. Action-items dates are bare
    /// calendar dates; what matters is that parse + display use the same zone.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let recognizedEmojiPrefixes: Set<String> = ["🔴", "🟡", "🟢", "💡", "📅", "✅", "📋"]

    private static func isRecognizedEmoji(_ s: String) -> Bool {
        if recognizedEmojiPrefixes.contains(s) { return true }
        if let first = s.unicodeScalars.first,
           (0x2600...0x27BF).contains(Int(first.value))
           || (0x1F300...0x1FAFF).contains(Int(first.value)) {
            return true
        }
        return false
    }

    /// 1 tab = 1 level, otherwise 2 spaces = 1 level.
    static func indentLevelFor(_ indent: String) -> Int {
        var tabs = 0
        var spaces = 0
        for ch in indent {
            if ch == "\t" { tabs += 1 }
            else if ch == " " { spaces += 1 }
        }
        return tabs + spaces / 2
    }

    static func kindFor(emoji: String, title: String) -> ActionSection.Kind {
        switch emoji {
        case "🔴": return .urgent
        case "🟡": return .todo
        case "🟢": return .watching
        case "💡": return .focus
        case "📅": return .meetings
        case "✅": return .done
        case "📋": return .digest
        default: break
        }
        if title.lowercased().contains("personal") { return .personal }
        return .neutral
    }

    /// Split a task line into (subject, body) on the first ` — ` / ` – ` / ` - `
    /// that falls outside markdown tokens. Falls back to `": "`.
    static func splitSubjectBody(_ rest: String) -> (String, String) {
        let separators = [" — ", " – ", " - "]
        if let idx = firstSeparatorOutsideTokens(in: rest, separators: separators) {
            for sep in separators {
                let sepLen = sep.count
                if rest.distance(from: idx, to: rest.endIndex) >= sepLen,
                   rest[idx ..< rest.index(idx, offsetBy: sepLen)] == sep {
                    return (
                        String(rest[..<idx]).trimmingCharacters(in: .whitespaces),
                        String(rest[rest.index(idx, offsetBy: sepLen)...]).trimmingCharacters(in: .whitespaces)
                    )
                }
            }
        }
        if let idx = firstSeparatorOutsideTokens(in: rest, separators: [": "]) {
            let sepLen = 2
            return (
                String(rest[..<idx]).trimmingCharacters(in: .whitespaces),
                String(rest[rest.index(idx, offsetBy: sepLen)...]).trimmingCharacters(in: .whitespaces)
            )
        }
        return (rest, "")
    }

    private static func firstSeparatorOutsideTokens(in text: String, separators: [String]) -> String.Index? {
        var inBold = false, inStrike = false, inCode = false
        var bracketDepth = 0, parenDepth = 0
        var i = text.startIndex
        while i < text.endIndex {
            let rem = text[i...]
            let two = rem.prefix(2)
            let ch = text[i]
            if ch == "`" && !inBold && !inStrike { inCode.toggle(); i = text.index(after: i); continue }
            if inCode { i = text.index(after: i); continue }
            if two == "**" { inBold.toggle(); i = text.index(i, offsetBy: 2); continue }
            if two == "~~" { inStrike.toggle(); i = text.index(i, offsetBy: 2); continue }
            if two == "[[" { bracketDepth += 1; i = text.index(i, offsetBy: 2); continue }
            if two == "]]" && bracketDepth > 0 { bracketDepth -= 1; i = text.index(i, offsetBy: 2); continue }
            if ch == "[" && bracketDepth == 0 { bracketDepth = 1; i = text.index(after: i); continue }
            if ch == "]" && bracketDepth > 0 && two != "]]" {
                bracketDepth = 0
                let next = text.index(after: i)
                if next < text.endIndex && text[next] == "(" {
                    parenDepth = 1
                    i = text.index(i, offsetBy: 2); continue
                }
                i = text.index(after: i); continue
            }
            if ch == ")" && parenDepth > 0 { parenDepth -= 1; i = text.index(after: i); continue }
            if !inBold && !inStrike && bracketDepth == 0 && parenDepth == 0 {
                for sep in separators {
                    let sepLen = sep.count
                    if text.distance(from: i, to: text.endIndex) >= sepLen,
                       text[i ..< text.index(i, offsetBy: sepLen)] == sep {
                        return i
                    }
                }
            }
            i = text.index(after: i)
        }
        return nil
    }
}
