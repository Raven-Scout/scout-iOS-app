import Foundation

/// Mutates the daily action-items markdown directly (the iOS app has no
/// scoutctl). All edits are line-targeted: the task line is re-located by its
/// stable `[#TAG]` prefix when present, falling back to the parsed line
/// number + plain-subject verification. Edits go through coordinated
/// read-modify-write so iCloud/Obsidian writes don't get clobbered.
enum ActionItemsWriter {

    enum WriteError: LocalizedError {
        case taskNotFound
        var errorDescription: String? {
            "Couldn't find this task in the file anymore — it may have been edited elsewhere. Pull to refresh."
        }
    }

    static func markDone(_ task: ActionTask, done: Bool, in relativePath: String, vault: VaultAccess) throws {
        try vault.modifyTextFile(relativePath: relativePath) { text in
            var lines = text.components(separatedBy: "\n")
            guard let idx = locateTaskLine(task, in: lines) else { throw WriteError.taskNotFound }
            let line = lines[idx]
            if done {
                guard let r = line.range(of: "- [ ]") else { throw WriteError.taskNotFound }
                lines[idx] = line.replacingCharacters(in: r, with: "- [x]")
            } else {
                if let r = line.range(of: "- [x]") {
                    lines[idx] = line.replacingCharacters(in: r, with: "- [ ]")
                } else if let r = line.range(of: "- [X]") {
                    lines[idx] = line.replacingCharacters(in: r, with: "- [ ]")
                } else {
                    throw WriteError.taskNotFound
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Appends a `- snoozed-until: YYYY-MM-DD (from-kind: <kind>)` sub-bullet
    /// under the task — the marker shape scoutctl and both apps parse.
    static func snooze(_ task: ActionTask, until: Date, fromKind: ActionSection.Kind?, in relativePath: String, vault: VaultAccess) throws {
        let dateStr = ActionItemsParser.dayFormatter.string(from: until)
        var marker = "  - snoozed-until: \(dateStr)"
        if let fromKind, fromKind != .neutral {
            marker += " (from-kind: \(fromKind.rawValue))"
        }
        try insertSubLine(marker, for: task, in: relativePath, vault: vault, replacingExistingSnooze: true)
    }

    /// Appends a `- <author>: <text>` sub-bullet comment under the task.
    static func addComment(_ task: ActionTask, author: String, text: String, in relativePath: String, vault: VaultAccess) throws {
        let sanitized = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !sanitized.isEmpty else { return }
        let safeAuthor = author.isEmpty ? "user" : author.replacingOccurrences(of: ":", with: "")
        try insertSubLine("  - \(safeAuthor): \(sanitized)", for: task, in: relativePath, vault: vault, replacingExistingSnooze: false)
    }

    // MARK: - Internals

    private static func insertSubLine(_ newLine: String, for task: ActionTask, in relativePath: String, vault: VaultAccess, replacingExistingSnooze: Bool) throws {
        try vault.modifyTextFile(relativePath: relativePath) { text in
            var lines = text.components(separatedBy: "\n")
            guard let idx = locateTaskLine(task, in: lines) else { throw WriteError.taskNotFound }
            var insertAt = idx + 1
            var existingSnoozeIdx: Int? = nil
            // Walk the task's attached block: indented sub-bullets/quotes that
            // are not themselves task lines.
            while insertAt < lines.count {
                let l = lines[insertAt]
                let trimmed = l.trimmingCharacters(in: .whitespaces)
                let isIndented = l.hasPrefix(" ") || l.hasPrefix("\t")
                let isTaskLine = trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]")
                guard isIndented, !trimmed.isEmpty, !isTaskLine else { break }
                if trimmed.hasPrefix("- snoozed-until:") { existingSnoozeIdx = insertAt }
                insertAt += 1
            }
            if replacingExistingSnooze, let existing = existingSnoozeIdx {
                lines[existing] = newLine
            } else {
                lines.insert(newLine, at: insertAt)
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Find the current line index (0-based) of `task`. Prefer the stable
    /// `[#TAG]` prefix; fall back to the parse-time line number when its
    /// content still matches; last resort is a plain-subject scan.
    static func locateTaskLine(_ task: ActionTask, in lines: [String]) -> Int? {
        func isTaskLine(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("- [ ]") || t.hasPrefix("- [x]") || t.hasPrefix("- [X]")
        }
        if let prefix = task.shortPrefix {
            let marker = "[#\(prefix)]"
            let matches = lines.indices.filter { isTaskLine(lines[$0]) && lines[$0].contains(marker) }
            if matches.count == 1 { return matches[0] }
            if matches.count > 1 {
                // Prefer the one nearest the original line number.
                return matches.min { abs($0 - (task.lineNumber - 1)) < abs($1 - (task.lineNumber - 1)) }
            }
        }
        let originalIdx = task.lineNumber - 1
        if originalIdx >= 0 && originalIdx < lines.count,
           isTaskLine(lines[originalIdx]),
           lineMatchesSubject(lines[originalIdx], task: task) {
            return originalIdx
        }
        return lines.firstIndex { isTaskLine($0) && lineMatchesSubject($0, task: task) }
    }

    private static func lineMatchesSubject(_ line: String, task: ActionTask) -> Bool {
        let needle = task.plainSubject.prefix(40)
        guard !needle.isEmpty else { return false }
        return ActionItemsParser.plainSubject(line).contains(needle)
    }
}
