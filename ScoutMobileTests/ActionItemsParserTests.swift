import Testing
import Foundation
@testable import ScoutMobile

struct ActionItemsParserTests {

    func fixture(_ name: String, ext: String) throws -> String {
        let url = try #require(Bundle(for: FixtureToken.self).url(forResource: name, withExtension: ext))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parsesFullDocument() throws {
        let text = try fixture("action-items-2026-04-20", ext: "md")
        let doc = try ActionItemsParser.parse(
            text: text,
            sourceURL: URL(fileURLWithPath: "action-items/action-items-2026-04-20.md"),
            sourceBytes: text.utf8.count
        )
        #expect(!doc.title.isEmpty)
        #expect(!doc.sections.isEmpty)
        let allTasks = doc.sections.flatMap(\.tasks)
        #expect(!allTasks.isEmpty)
    }

    @Test func sectionKindsResolve() {
        #expect(ActionItemsParser.kindFor(emoji: "🔴", title: "Urgent") == .urgent)
        #expect(ActionItemsParser.kindFor(emoji: "🟡", title: "To Do") == .todo)
        #expect(ActionItemsParser.kindFor(emoji: "🟢", title: "Watching") == .watching)
        #expect(ActionItemsParser.kindFor(emoji: "💡", title: "Focus") == .focus)
        #expect(ActionItemsParser.kindFor(emoji: "📅", title: "Meetings") == .meetings)
        #expect(ActionItemsParser.kindFor(emoji: "", title: "Personal stuff") == .personal)
        #expect(ActionItemsParser.kindFor(emoji: "", title: "Misc") == .neutral)
    }

    @Test func extractsShortPrefix() {
        let (p1, r1) = ActionItemsParser.extractShortPrefix("[#AB30] **Subject**")
        #expect(p1 == "AB30")
        #expect(r1 == "**Subject**")

        // Pure numeric is a GitHub ref, not a prefix.
        let (p2, _) = ActionItemsParser.extractShortPrefix("[#5864] thing")
        #expect(p2 == nil)

        // Widened grammar: 2–8 chars.
        let (p3, _) = ActionItemsParser.extractShortPrefix("[#RSM] thing")
        #expect(p3 == "RSM")
        let (p4, _) = ActionItemsParser.extractShortPrefix("[#AI3026] thing")
        #expect(p4 == "AI3026")
    }

    @Test func detectsDeepLinks() {
        let links = ActionItemsParser.detectDeepLinks(
            in: "Check PROJ-3026 and https://github.com/example-org/example-repo/pull/6218 plus https://example.slack.com/archives/C0123456789/p1700000000000000"
        )
        #expect(links.count == 3)
        guard case .linear(let id) = links[0] else { Issue.record("expected linear first"); return }
        #expect(id == "PROJ-3026")
        guard case .githubPR(let repo, let n, _) = links[1] else { Issue.record("expected github PR"); return }
        #expect(repo == "example-org/example-repo")
        #expect(n == 6218)
        guard case .slackThread = links[2] else { Issue.record("expected slack thread"); return }
    }

    @Test func parsesSnoozeSubBullet() throws {
        let text = """
        # Action Items — 2026-06-01

        ## 🔴 Urgent
        - [ ] [#AB12] **Do the thing** — important
          - snoozed-until: 2026-06-05 (from-kind: urgent)
        """
        let doc = try ActionItemsParser.parse(
            text: text,
            sourceURL: URL(fileURLWithPath: "action-items-2026-06-01.md"),
            sourceBytes: text.utf8.count
        )
        let task = try #require(doc.sections.first?.tasks.first)
        #expect(task.snoozedUntil != nil)
        #expect(task.snoozedFromKind == .urgent)
        #expect(task.comments.isEmpty)   // snooze marker must NOT surface as a comment
    }

    @Test func parsesComments() throws {
        let text = """
        # Action Items — 2026-06-01

        ## 🟡 To Do
        - [ ] [#CM01] **Commented task** — has feedback
          > alex (2026-06-01 9:15 AM): blockquote comment
          - alex: sub-bullet comment
        """
        let doc = try ActionItemsParser.parse(
            text: text,
            sourceURL: URL(fileURLWithPath: "action-items-2026-06-01.md"),
            sourceBytes: text.utf8.count
        )
        let task = try #require(doc.sections.first?.tasks.first)
        #expect(task.comments.count == 2)
        #expect(task.comments[0].author == "alex")
        #expect(task.comments[0].timestamp == "2026-06-01 9:15 AM")
        #expect(task.comments[1].text == "sub-bullet comment")
    }

    @Test func parsesMeetingsTable() throws {
        let text = """
        # Action Items — 2026-06-01

        ## 📅 Meetings
        | Time | Meeting | Prep |
        | --- | --- | --- |
        | 10:00 | Standup | none |
        | 15:00 | Sharing | agenda |
        """
        let doc = try ActionItemsParser.parse(
            text: text,
            sourceURL: URL(fileURLWithPath: "action-items-2026-06-01.md"),
            sourceBytes: text.utf8.count
        )
        let section = try #require(doc.sections.first)
        #expect(section.kind == .meetings)
        let table = try #require(section.tables.first)
        #expect(table.headers == ["Time", "Meeting", "Prep"])
        #expect(table.rows.count == 2)
    }
}

final class FixtureToken {}
