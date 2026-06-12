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
        let expected: Expected

        struct Expected: Decodable {
            let short_prefix: String?
            let subject: String
            let plain_subject: String
            let body: String
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
}

private final class BundleToken {}
