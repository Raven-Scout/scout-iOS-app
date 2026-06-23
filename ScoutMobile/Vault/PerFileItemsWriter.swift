import Foundation

/// A resolution the app can write back to a per-file item.
enum ItemResolution: Sendable, Equatable {
    case done, dropped
    var status: ItemStatus { self == .done ? .done : .dropped }
}

/// Creates per-file items and resolves them, writing directly to the vault
/// (the iOS app has no scoutctl and no git — items are plain markdown that
/// dreaming/research sessions and Obsidian also read and write).
///
/// Add renders a `YYYY-MM-DD-slug.md` file via `VaultAccess.createUniqueFile`.
/// Resolve flips the frontmatter `status:` line in place via
/// `VaultAccess.modifyTextFile` — leaving every other byte identical, the same
/// line-targeted hygiene as `ProposalsWriter`.
enum PerFileItemsWriter {

    enum WriteError: LocalizedError, Equatable {
        case emptyTitle
        case frontmatterNotFound
        case statusFieldNotFound

        var errorDescription: String? {
            switch self {
            case .emptyTitle:
                return "Give the item a title."
            case .frontmatterNotFound:
                return "This file has no frontmatter to update — it may have been edited elsewhere. Pull to refresh."
            case .statusFieldNotFound:
                return "This item has no status field to update."
            }
        }
    }

    // MARK: - Mutations

    /// Render and create a new item file. Returns its vault-relative path.
    @discardableResult
    static func addItem(
        config: PerFileTabConfig,
        title: String,
        priority: ItemPriority,
        body: String,
        optional: String?,
        vault: VaultAccess,
        now: Date = Date()
    ) throws -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw WriteError.emptyTitle }

        var source: String?
        var area: String?
        switch config.optionalField {
        case .none: break
        case .source: source = optional?.nilIfBlank
        case .area: area = optional?.nilIfBlank
        }

        let date = isoDate(now)
        let text = renderItemFile(title: cleanTitle, status: .open, priority: priority,
                                  date: date, source: source, area: area, body: body)
        let base = "\(date)-\(slugify(cleanTitle))"
        return try vault.createUniqueFile(inDirectory: config.directory, baseName: base, contents: text)
    }

    /// Flip a per-file item's frontmatter `status:` to done/dropped in place.
    static func resolve(_ resolution: ItemResolution, item: PerFileItem, vault: VaultAccess) throws {
        try vault.modifyTextFile(relativePath: item.relativePath) { text in
            try rewriteFrontmatterStatus(text: text, newStatusValue: resolution.status.frontmatterValue)
        }
    }

    // MARK: - Pure helpers (unit-tested directly)

    static func slugify(_ title: String, maxWords: Int = 8) -> String {
        let mapped = title.lowercased().map { ch -> Character in
            (("a"..."z").contains(ch) || ("0"..."9").contains(ch)) ? ch : " "
        }
        let words = String(mapped).split(separator: " ").prefix(maxWords)
        return words.joined(separator: "-")
    }

    static func renderItemFile(title: String, status: ItemStatus, priority: ItemPriority,
                               date: String, source: String?, area: String?, body: String) -> String {
        func yq(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        var fm = ["---", "title: \(yq(title))", "status: \(status.frontmatterValue)",
                  "priority: \(priority.rawValue)", "date: \(date)"]
        if let source, !source.isEmpty { fm.append("source: \(yq(source))") }
        if let area, !area.isEmpty { fm.append("area: \(yq(area))") }
        fm.append("---")
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return fm.joined(separator: "\n") + "\n\n# \(title)\n\n" + trimmedBody + "\n"
    }

    /// Replace the value of the frontmatter `status:` line, preserving leading
    /// indentation and every other byte. Throws if there is no frontmatter or
    /// no status field.
    static func rewriteFrontmatterStatus(text: String, newStatusValue: String) throws -> String {
        var lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            throw WriteError.frontmatterNotFound
        }
        var i = 1
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespacesAndNewlines) == "---" { break }
            if let colon = lines[i].firstIndex(of: ":") {
                let key = lines[i][..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if key == "status" {
                    let leading = String(lines[i].prefix(while: { $0 == " " || $0 == "\t" }))
                    lines[i] = "\(leading)status: \(newStatusValue)"
                    return lines.joined(separator: "\n")
                }
            }
            i += 1
        }
        throw WriteError.statusFieldNotFound
    }

    // MARK: - Date

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
