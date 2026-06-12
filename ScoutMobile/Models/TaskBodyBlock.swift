import Foundation

/// A structural block parsed out of a task body. Scout writes task bodies as
/// one dense run — bold-label clauses (`**Why:** …`), inline `(1)…(2)…`
/// checklists, and a trailing cluster of `[[wikilinks]]`. `TaskBodyParser`
/// breaks that run into typed blocks so the expanded card can lay each out
/// with its own typography. Ported from the desktop app.
enum TaskBodyBlock: Equatable {
    case paragraph(label: String?, text: String)
    case steps(label: String?, items: [String])
    case links([String])
}

enum TaskBodyParser {
    static func blocks(from rawBody: String) -> [TaskBodyBlock] {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return [] }

        let (prose, linkTargets) = splitTrailingLinks(body)

        var blocks: [TaskBodyBlock] = []
        for segment in labeledSegments(prose) {
            blocks.append(contentsOf: segmentBlocks(label: segment.label, text: segment.text))
        }
        if blocks.isEmpty && !prose.isEmpty {
            blocks.append(.paragraph(label: nil, text: prose))
        }
        if !linkTargets.isEmpty {
            blocks.append(.links(linkTargets))
        }
        return blocks
    }

    // MARK: - Trailing links

    private static func splitTrailingLinks(_ body: String) -> (prose: String, targets: [String]) {
        guard let re = try? NSRegularExpression(pattern: #"((?:\s*\[\[[^\]]+\]\])+)\s*$"#) else {
            return (body, [])
        }
        let ns = body as NSString
        guard let m = re.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)) else {
            return (body, [])
        }
        let cluster = ns.substring(with: m.range(at: 1))
        let targets = wikilinkTargets(in: cluster)
        guard targets.count >= 2 else { return (body, []) }
        let prose = ns.substring(to: m.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
        return (prose, targets)
    }

    static func wikilinkTargets(in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"\[\[([^\]|]+?)(?:\|[^\]]+)?\]\]"#) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
        }
    }

    // MARK: - Labeled segments

    private struct Segment { let label: String?; let text: String }

    private static func labeledSegments(_ prose: String) -> [Segment] {
        guard !prose.isEmpty else { return [] }
        guard let re = try? NSRegularExpression(pattern: #"\*\*\s*([^*\n]{1,48}?)\s*:\s*\*\*"#) else {
            return [Segment(label: nil, text: prose)]
        }
        let ns = prose as NSString
        let matches = re.matches(in: prose, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [Segment(label: nil, text: prose)] }

        var segments: [Segment] = []
        let leadEnd = matches[0].range.location
        if leadEnd > 0 {
            let lead = trimSeparators(ns.substring(to: leadEnd))
            if !lead.isEmpty { segments.append(Segment(label: nil, text: lead)) }
        }
        for (i, m) in matches.enumerated() {
            let label = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let textStart = m.range.location + m.range.length
            let textEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
            let text = trimSeparators(ns.substring(with: NSRange(location: textStart, length: textEnd - textStart)))
            segments.append(Segment(label: label, text: text))
        }
        return segments
    }

    // MARK: - Step detection

    private static func segmentBlocks(label: String?, text: String) -> [TaskBodyBlock] {
        guard let steps = inlineSteps(in: text) else {
            return text.isEmpty && label != nil
                ? [.paragraph(label: label, text: "")]
                : [.paragraph(label: label, text: text)]
        }
        var out: [TaskBodyBlock] = []
        if !steps.preface.isEmpty {
            out.append(.paragraph(label: label, text: steps.preface))
            out.append(.steps(label: nil, items: steps.items))
        } else {
            out.append(.steps(label: label, items: steps.items))
        }
        return out
    }

    private static func inlineSteps(in text: String) -> (preface: String, items: [String])? {
        guard let re = try? NSRegularExpression(pattern: #"\((\d+)\)"#) else { return nil }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard matches.count >= 2 else { return nil }
        for (i, m) in matches.enumerated() {
            guard Int(ns.substring(with: m.range(at: 1))) == i + 1 else { return nil }
        }
        let preface = trimSeparators(ns.substring(to: matches[0].range.location))
        var items: [String] = []
        for (i, m) in matches.enumerated() {
            let start = m.range.location + m.range.length
            let end = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
            var item = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespaces)
            while let last = item.last, ";.,".contains(last) { item.removeLast() }
            items.append(item.trimmingCharacters(in: .whitespaces))
        }
        return (preface, items)
    }

    private static func trimSeparators(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for joiner in ["— ", "– ", "- "] where out.hasPrefix(joiner) {
            out = String(out.dropFirst(joiner.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return out
    }
}
