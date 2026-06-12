import Foundation

/// One quote-line or sub-bullet comment bound to a task.
/// Source shapes: `  > author (2026-04-18 10:20 AM ET): text`
///                `  - author: text`
struct TaskComment: Equatable, Hashable, Sendable {
    let author: String
    /// Free-form timestamp as written in the file. May be empty.
    let timestamp: String
    let text: String
}

enum TaskDeepLink: Equatable, Hashable, Sendable, Identifiable {
    case linear(id: String)
    case githubPR(repo: String, number: Int, rawURL: URL)
    case slackThread(URL)

    var id: String {
        switch self {
        case .linear(let id):               return "linear:\(id)"
        case .githubPR(let repo, let n, _): return "gh:\(repo)#\(n)"
        case .slackThread(let url):         return "slack:\(url.absoluteString)"
        }
    }

    var displayLabel: String {
        switch self {
        case .linear(let id):               return id
        case .githubPR(let repo, let n, _): return "\(repo.split(separator: "/").last.map(String.init) ?? repo)#\(n)"
        case .slackThread:                  return "Slack thread"
        }
    }

    var systemImage: String {
        switch self {
        case .linear:      return "circle.hexagongrid"
        case .githubPR:    return "arrow.triangle.pull"
        case .slackThread: return "bubble.left.and.bubble.right"
        }
    }

    /// Web URL for this link. Linear needs the workspace slug from Settings.
    func webURL(linearWorkspace: String) -> URL {
        switch self {
        case .linear(let id):
            if linearWorkspace.isEmpty { return URL(string: "https://linear.app/")! }
            return URL(string: "https://linear.app/\(linearWorkspace)/issue/\(id)")!
        case .githubPR(_, _, let raw):
            return raw
        case .slackThread(let url):
            return url
        }
    }
}

struct ActionTask: Identifiable, Equatable, Hashable, Sendable {
    /// Ephemeral; regenerated on each parse. Do not persist.
    let id: UUID
    /// 1-based line number in the source file.
    let lineNumber: Int
    let done: Bool
    /// Raw markdown subject (with `**bold**`, `[[wikilinks]]`, etc.).
    let subject: String
    /// Markdown-stripped subject. MUST match the Python CLIs'
    /// `_strip_markdown_tokens` output byte-for-byte.
    let plainSubject: String
    /// Post-dash/colon remainder. May be empty.
    let body: String
    let comments: [TaskComment]
    let deepLinks: [TaskDeepLink]
    /// Parsed from a `— 🛌 Snoozed until YYYY-MM-DD` body suffix or a
    /// `- snoozed-until:` sub-bullet. `nil` otherwise.
    let snoozedUntil: Date?
    /// Parsed from a `_(carried in from YYYY-MM-DD)_` body marker.
    let carriedInFrom: Date?
    /// Markdown-list nesting depth (0 = top-level).
    let indentLevel: Int
    /// Stable `[#TAG]` id (2–8 [A-Z0-9], ≥1 letter), if present.
    let shortPrefix: String?
    /// Source section kind recorded in the snoozed-until marker.
    let snoozedFromKind: ActionSection.Kind?

    init(
        id: UUID,
        lineNumber: Int,
        done: Bool,
        subject: String,
        plainSubject: String,
        body: String,
        comments: [TaskComment],
        deepLinks: [TaskDeepLink],
        snoozedUntil: Date?,
        carriedInFrom: Date?,
        indentLevel: Int = 0,
        shortPrefix: String? = nil,
        snoozedFromKind: ActionSection.Kind? = nil
    ) {
        self.id = id
        self.lineNumber = lineNumber
        self.done = done
        self.subject = subject
        self.plainSubject = plainSubject
        self.body = body
        self.comments = comments
        self.deepLinks = deepLinks
        self.snoozedUntil = snoozedUntil
        self.carriedInFrom = carriedInFrom
        self.indentLevel = indentLevel
        self.shortPrefix = shortPrefix
        self.snoozedFromKind = snoozedFromKind
    }

    func with(comments newComments: [TaskComment]? = nil, snoozedUntil newSnooze: Date?? = nil, snoozedFromKind newKind: ActionSection.Kind?? = nil) -> ActionTask {
        ActionTask(
            id: id, lineNumber: lineNumber, done: done,
            subject: subject, plainSubject: plainSubject, body: body,
            comments: newComments ?? comments, deepLinks: deepLinks,
            snoozedUntil: newSnooze ?? snoozedUntil, carriedInFrom: carriedInFrom,
            indentLevel: indentLevel, shortPrefix: shortPrefix,
            snoozedFromKind: newKind ?? snoozedFromKind
        )
    }
}

struct ActionSection: Identifiable, Equatable, Hashable, Sendable {
    enum Kind: String, Equatable, Hashable, Sendable {
        case urgent, todo, watching, personal
        case focus, meetings, done, digest
        case neutral
    }

    struct Table: Equatable, Hashable, Sendable {
        let headers: [String]
        let rows: [[String]]
    }

    let id: UUID
    /// Section heading emoji (e.g. "🔴"), or empty for plain-title sections.
    let emoji: String
    /// Section heading title without the emoji prefix.
    let title: String
    let kind: Kind
    let tasks: [ActionTask]
    /// Non-task bullets (used in 💡 Focus and 📋 Digest).
    let bullets: [String]
    /// Tables (used in 📅 Meetings).
    let tables: [Table]
    /// `### subheads` found inside this section.
    let subheads: [String]
}

struct ActionItemsDocument: Equatable, Hashable, Sendable {
    /// Calendar date parsed from the filename.
    let date: Date
    /// H1 title.
    let title: String
    /// Paragraphs between the H1 and the first H2.
    let preamble: [String]
    let sections: [ActionSection]
    let sourceURL: URL
    /// Cheap change signal — file size in bytes at the time of parse.
    let sourceBytes: Int

    var openCount: Int {
        sections.flatMap(\.tasks).filter { !$0.done }.count
    }
    var doneCount: Int {
        sections.flatMap(\.tasks).filter(\.done).count
    }
}
