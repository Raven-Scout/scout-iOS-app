import Foundation

/// A single dreaming proposal parsed from `dreaming-proposals.md`.
///
/// Each proposal is a `### <code> — <title>` section followed by a
/// `**Status:**` line and free-form markdown body. `headingLine` is the exact
/// `### …` source line; it is both the stable identity for SwiftUI and the
/// match key the writer uses to relocate the section when flipping status
/// (the file is rewritten between parses, so line numbers are not trusted —
/// the same stable-identity approach the action-items writer uses).
struct Proposal: Identifiable, Equatable, Sendable {
    /// Exact `### …` heading line, verbatim from the file.
    let headingLine: String
    /// Display code lifted from the heading (e.g. `P-2026-06-13-01`, or a bare
    /// date for template-style headings). Empty if the heading has no ` — `.
    let code: String
    /// Title text after the ` — ` separator (or the whole heading if none).
    let title: String
    /// Parsed status.
    let status: ProposalStatus
    /// Everything in the section except the heading and the `**Status:**` line.
    let bodyMarkdown: String

    var id: String { headingLine }

    var isAwaitingDecision: Bool { status.isAwaitingDecision }

    /// Structured body blocks for rendering (prose paragraphs + code blocks).
    var bodyBlocks: [ProposalBodyBlock] { ProposalBodyBlock.blocks(from: bodyMarkdown) }
}

/// Lifecycle status of a dreaming proposal, parsed from the `**Status:**` line
/// of a proposal section in `dreaming-proposals.md`.
///
/// The status vocabulary mirrors the scout-plugin feedback-processing spec:
/// a proposal moves `Proposed` / `Pending` → `Approved` or `Rejected`, and a
/// later dreaming run flips an approved (or ripe opt-out `Pending`) proposal to
/// `Applied`. The app only ever writes `Approved` / `Rejected` — applying the
/// underlying SKILL.md change stays with the dreaming run.
enum ProposalStatus: Equatable, Sendable {
    /// `Proposed (awaiting Adam approval)` — needs an explicit decision.
    case proposed
    /// `Pending (auto-apply after <date>)` — opt-out; auto-applies unless
    /// rejected. `autoApplyDate` is the ISO date when present.
    case pending(autoApplyDate: String?)
    /// `Approved …` — will be applied by the next dreaming run.
    case approved
    /// `Rejected …` — declined; will not be applied.
    case rejected
    /// `Applied — <date>` — already applied to SKILL.md.
    case applied(date: String?)
    /// Any status string we don't recognize; preserved verbatim for display.
    case unknown(String)

    /// Classify a raw status value (the text after `**Status:**`) by its
    /// leading word, case-insensitively. The leading word is what a dreaming
    /// run keys on, so anchoring on it keeps the app and engine in agreement.
    static func parse(_ rawValue: String) -> ProposalStatus {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("approved") { return .approved }
        if lower.hasPrefix("rejected") || lower.hasPrefix("declined") { return .rejected }
        if lower.hasPrefix("applied") { return .applied(date: Self.firstISODate(in: trimmed)) }
        if lower.hasPrefix("pending") { return .pending(autoApplyDate: Self.firstISODate(in: trimmed)) }
        if lower.hasPrefix("proposed") { return .proposed }
        return .unknown(trimmed)
    }

    /// True when the proposal is still waiting on the user's call — i.e. it
    /// drives the tab badge count and gets Approve/Decline buttons.
    var isAwaitingDecision: Bool {
        switch self {
        case .proposed, .pending: return true
        case .approved, .rejected, .applied, .unknown: return false
        }
    }

    var isResolved: Bool { !isAwaitingDecision }

    /// Short label for the status pill.
    var displayName: String {
        switch self {
        case .proposed:           return "Proposed"
        case .pending:            return "Pending"
        case .approved:           return "Approved"
        case .rejected:           return "Rejected"
        case .applied:            return "Applied"
        case .unknown(let raw):   return raw
        }
    }

    // MARK: - Helpers

    /// First `yyyy-MM-dd` substring, used to surface a `Pending` auto-apply
    /// date or an `Applied` date in the pill subtitle.
    private static func firstISODate(in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"\d{4}-\d{2}-\d{2}"#) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range)
    }
}

/// A structural block of a proposal body. Proposal bodies are free-form
/// markdown — bold-label paragraphs (`**Problem.** …`), prose, and fenced
/// code blocks (```bash … ```). Rendering them as one flat `Text` would mangle
/// the code, so the body is split into prose paragraphs (rendered with inline
/// markdown) and verbatim code blocks (rendered monospace).
enum ProposalBodyBlock: Equatable, Sendable, Identifiable {
    /// A paragraph of prose; may contain inline markdown (bold, links,
    /// `[[wikilinks]]`). Rendered via `InlineMarkdown.attributed`.
    case prose(String)
    /// A fenced code block, rendered verbatim in a monospace panel.
    case code(language: String?, code: String)

    var id: String {
        switch self {
        case .prose(let t):          return "p:\(t)"
        case .code(let lang, let c): return "c:\(lang ?? ""):\(c)"
        }
    }

    /// Split a raw proposal body into ordered blocks. Fenced code blocks
    /// (lines bounded by ```` ``` ````) are lifted out verbatim; the prose
    /// between them is broken into paragraphs on blank lines.
    static func blocks(from rawBody: String) -> [ProposalBodyBlock] {
        let lines = rawBody.components(separatedBy: "\n")
        var blocks: [ProposalBodyBlock] = []
        var proseBuffer: [String] = []
        var codeBuffer: [String] = []
        var codeLanguage: String?
        var inCode = false

        func flushProse() {
            let joined = proseBuffer.joined(separator: "\n")
            for para in paragraphs(in: joined) {
                blocks.append(.prose(para))
            }
            proseBuffer.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    // Closing fence — emit the accumulated code.
                    blocks.append(.code(language: codeLanguage,
                                        code: codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll(keepingCapacity: true)
                    codeLanguage = nil
                    inCode = false
                } else {
                    // Opening fence — flush any pending prose first.
                    flushProse()
                    let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLanguage = lang.isEmpty ? nil : lang
                    inCode = true
                }
                continue
            }
            if inCode {
                codeBuffer.append(line)
            } else {
                proseBuffer.append(line)
            }
        }

        // Unterminated fence (malformed markdown): keep its content as code so
        // nothing is dropped.
        if inCode {
            blocks.append(.code(language: codeLanguage, code: codeBuffer.joined(separator: "\n")))
        }
        flushProse()
        return blocks
    }

    /// Split a block of text into paragraphs on runs of blank lines, trimming
    /// surrounding whitespace and dropping empties.
    private static func paragraphs(in text: String) -> [String] {
        text
            .components(separatedBy: "\n")
            .reduce(into: [[String]]()) { acc, line in
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    if acc.last?.isEmpty == false { acc.append([]) }
                } else {
                    if acc.isEmpty { acc.append([]) }
                    acc[acc.count - 1].append(line)
                }
            }
            .map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
