import Testing
import Foundation
@testable import ScoutMobile

/// The writer mutates markdown directly (no scoutctl on iOS); these tests
/// exercise the line-location and edit logic against parsed fixtures.
struct ActionItemsWriterTests {

    let sample = """
    # Action Items — 2026-06-01

    ## 🔴 Urgent
    - [ ] [#AB12] **First task** — details here
      - Source: somewhere
      - Context: [[backend-service]]
    - [x] [#CD34] **Done task** — finished
    - [ ] Unprefixed legacy task — still matched by subject

    ## 🟡 To Do
    - [ ] [#EF56] **Second task** — more details
    """

    func parsedTasks() throws -> [ActionTask] {
        let doc = try ActionItemsParser.parse(
            text: sample,
            sourceURL: URL(fileURLWithPath: "action-items-2026-06-01.md"),
            sourceBytes: sample.utf8.count
        )
        return doc.sections.flatMap(\.tasks)
    }

    @Test func locatesByPrefix() throws {
        let tasks = try parsedTasks()
        let lines = sample.components(separatedBy: "\n")
        let first = try #require(tasks.first { $0.shortPrefix == "AB12" })
        let idx = try #require(ActionItemsWriter.locateTaskLine(first, in: lines))
        #expect(lines[idx].contains("[#AB12]"))
    }

    @Test func locatesLegacyBySubject() throws {
        let tasks = try parsedTasks()
        let legacy = try #require(tasks.first { $0.shortPrefix == nil })
        let lines = sample.components(separatedBy: "\n")
        let idx = try #require(ActionItemsWriter.locateTaskLine(legacy, in: lines))
        #expect(lines[idx].contains("Unprefixed legacy task"))
    }

    @Test func locatesAfterLinesShifted() throws {
        let tasks = try parsedTasks()
        let second = try #require(tasks.first { $0.shortPrefix == "EF56" })
        // Simulate Scout inserting lines above (line numbers now stale).
        let shifted = "# Action Items — 2026-06-01\n\nNEW LINE\nNEW LINE\n"
            + sample.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n")
        let lines = shifted.components(separatedBy: "\n")
        let idx = try #require(ActionItemsWriter.locateTaskLine(second, in: lines))
        #expect(lines[idx].contains("[#EF56]"))
    }
}
