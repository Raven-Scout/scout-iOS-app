import Foundation

/// Pure parser for one per-file item (YAML frontmatter + markdown body).
/// Ported from the desktop app (Scout/PerFileItems/PerFileItemParser.swift).
/// Returns nil when the file has no frontmatter (skips index/non-item files).
enum PerFileItemParser {
    static func parseFile(contents: String, relativePath: String) -> PerFileItem? {
        guard let (frontmatter, body) = splitFrontmatter(contents) else { return nil }
        let fields = parseFrontmatterFields(frontmatter)
        let stem = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension

        let date = fields["date"]?.nonEmpty ?? datePrefix(of: stem) ?? ""
        let title = fields["title"]?.nonEmpty ?? stem
        let status = ItemStatus.parse(fields["status"] ?? "")
        let priority = ItemPriority.parse(fields["priority"] ?? "")
        let source = fields["source"]?.nonEmpty
        let area = fields["area"]?.nonEmpty
        let cleanBody = stripLeadingHeading(body).trimmingCharacters(in: .whitespacesAndNewlines)

        return PerFileItem(relativePath: relativePath, date: date, title: title, status: status,
                           priority: priority, source: source, area: area, bodyMarkdown: cleanBody)
    }

    static func splitFrontmatter(_ text: String) -> (frontmatter: String, body: String)? {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return nil }
        var frontmatter: [String] = []
        var i = 1
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespacesAndNewlines) == "---" {
                let body = i + 1 < lines.count ? lines[(i + 1)...].joined(separator: "\n") : ""
                return (frontmatter.joined(separator: "\n"), body)
            }
            frontmatter.append(lines[i])
            i += 1
        }
        return nil
    }

    static func parseFrontmatterFields(_ frontmatter: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in frontmatter.components(separatedBy: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { continue }
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = unescapeQuoted(String(value.dropFirst().dropLast()))
            }
            out[key] = value
        }
        return out
    }

    static func stripLeadingHeading(_ body: String) -> String {
        var lines = body.components(separatedBy: "\n")
        while let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeFirst()
        }
        if let first = lines.first, first.hasPrefix("# "), !first.hasPrefix("## ") {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n")
    }

    static func datePrefix(of stem: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}"#) else { return nil }
        let ns = stem as NSString
        guard let m = re.firstMatch(in: stem, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range)
    }

    /// Reverse the writer's YAML double-quote escaping (`\\` → `\`, `\"` → `"`),
    /// scanning left-to-right so a backslash always consumes the next character
    /// literally. Applied only to quoted values — the only ones the writer escapes.
    static func unescapeQuoted(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var escaped = false
        for ch in s {
            if escaped {
                out.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else {
                out.append(ch)
            }
        }
        if escaped { out.append("\\") }  // trailing lone backslash — keep it
        return out
    }
}

private extension String {
    var nonEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
