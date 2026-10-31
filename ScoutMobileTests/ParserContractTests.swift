import Testing
import Foundation
@testable import ScoutMobile

/// Asserts the line-level parser against the cross-platform contract corpus
/// (`parser-corpus.json`, byte-identical to the desktop app's and the
/// plugin's copies).
struct ParserContractTests {

    struct CorpusEntry: Decodable {
        let name: String
        let line: String
        let sub_lines: [String]?
        let expected: Expected

        struct Block: Decodable, Equatable {
            let date: String
            let start: String
            let end: String
            let minutes: Int
            let event_id: String?
        }

        struct Plan: Decodable, Equatable {
            let estimate_minutes: Int?
            let raw_minutes: Int?
            let kind: String?
            let block: Block?
            let actual_minutes: Int?
            let actual_date: String?
        }

        struct Expected: Decodable {
            let short_prefix: String?
            let subject: String
            let plain_subject: String
            let body: String
            let plan: Plan?
            let comment_authors: [String]?
        }
    }

    struct Corpus: Decodable {
        let entries: [CorpusEntry]
    }

    static func loadCorpus() throws -> [CorpusEntry] {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "parser-corpus", withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Corpus.self, from: data).entries
    }

    @Test func corpusEntriesMatch() throws {
        let entries = try Self.loadCorpus()
        #expect(!entries.isEmpty)
        let taskRe = try NSRegularExpression(pattern: #"^(\s*)- \[([ xX])\] (.+?)\s*$"#)

        for entry in entries {
            let line = entry.line
            let range = NSRange(line.startIndex..., in: line)
            let m = try #require(taskRe.firstMatch(in: line, range: range), "task line should match: \(entry.name)")
            let rest = (line as NSString).substring(with: m.range(at: 3))

            let (prefix, withoutPrefix) = ActionItemsParser.extractShortPrefix(rest)
            let (subject, body) = ActionItemsParser.splitSubjectBody(withoutPrefix)
            let plain = ActionItemsParser.plainSubject(subject)

            #expect(prefix == entry.expected.short_prefix, "short_prefix mismatch in \(entry.name)")
            #expect(subject == entry.expected.subject, "subject mismatch in \(entry.name)")
            #expect(plain == entry.expected.plain_subject, "plain_subject mismatch in \(entry.name)")
            #expect(body == entry.expected.body, "body mismatch in \(entry.name)")
        }
    }

    /// `/scout-plan` marker entries: the plan and the comments of the top-level
    /// task, parsed from the whole entry the way the desktop app and the engine
    /// do. (This app has no board fields, so field entries are not checked here.)
    @Test func planMarkerEntriesMatch() throws {
        let entries = try Self.loadCorpus().filter { $0.expected.plan != nil }
        #expect(!entries.isEmpty)
        let url = URL(fileURLWithPath: "/tmp/action-items-2026-04-20.md")
        for entry in entries {
            let text = "# T\n\n## 🔴 Urgent\n\n" + ([entry.line] + (entry.sub_lines ?? [])).joined(separator: "\n") + "\n"
            let doc = try ActionItemsParser.parse(text: text, sourceURL: url, sourceBytes: text.utf8.count)
            let task = try #require(doc.sections.flatMap(\.tasks).first { $0.indentLevel == 0 }, "\(entry.name): no task")
            let p = task.plan
            let plan = CorpusEntry.Plan(
                estimate_minutes: p.estimateMinutes, raw_minutes: p.rawMinutes, kind: p.kind,
                block: p.block.map {
                    CorpusEntry.Block(date: $0.date, start: $0.start, end: $0.end, minutes: $0.minutes, event_id: $0.eventID)
                },
                actual_minutes: p.actualMinutes, actual_date: p.actualDate
            )
            #expect(plan == entry.expected.plan, "plan mismatch in \(entry.name)")
            #expect(task.comments.map(\.author) == entry.expected.comment_authors, "comment_authors mismatch in \(entry.name)")
        }
    }
}

private final class BundleToken {}
