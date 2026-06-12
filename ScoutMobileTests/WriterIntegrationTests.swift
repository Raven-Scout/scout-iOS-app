import Testing
import Foundation
@testable import ScoutMobile

/// End-to-end write-path tests against a real temp-directory vault: bookmark
/// persistence, coordinated read-modify-write, and reparse round-trips.
struct WriterIntegrationTests {

    func makeVault() throws -> (vault: VaultAccess, dir: URL, defaults: UserDefaults) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("scout-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("action-items"), withIntermediateDirectories: true
        )
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        try VaultAccess.saveBookmark(for: dir, defaults: defaults)
        return (VaultAccess(defaults: defaults), dir, defaults)
    }

    let sample = """
    # Action Items — 2026-06-01

    ## 🔴 Urgent
    - [ ] [#AB12] **First task** — details here
      - Source: somewhere
    - [ ] [#CD34] **Second task** — more

    ## 🟢 Watching
    - [x] [#EF56] **Done already** — yep
    """

    let path = "action-items/action-items-2026-06-01.md"

    func parse(_ vault: VaultAccess) throws -> ActionItemsDocument {
        let data = try vault.readFile(relativePath: path)
        return try ActionItemsParser.parse(
            text: String(data: data, encoding: .utf8)!,
            sourceURL: URL(fileURLWithPath: path),
            sourceBytes: data.count
        )
    }

    @Test func markDoneRoundTrip() throws {
        let (vault, dir, _) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        try vault.writeFile(relativePath: path, data: Data(sample.utf8))

        var doc = try parse(vault)
        let task = try #require(doc.sections.flatMap(\.tasks).first { $0.shortPrefix == "AB12" })
        #expect(!task.done)

        try ActionItemsWriter.markDone(task, done: true, in: path, vault: vault)
        doc = try parse(vault)
        let after = try #require(doc.sections.flatMap(\.tasks).first { $0.shortPrefix == "AB12" })
        #expect(after.done)

        // And reopen.
        try ActionItemsWriter.markDone(after, done: false, in: path, vault: vault)
        doc = try parse(vault)
        let reopened = try #require(doc.sections.flatMap(\.tasks).first { $0.shortPrefix == "AB12" })
        #expect(!reopened.done)
        // Sub-bullets must survive untouched.
        let text = String(data: try vault.readFile(relativePath: path), encoding: .utf8)!
        #expect(text.contains("  - Source: somewhere"))
    }

    @Test func snoozeRoundTrip() throws {
        let (vault, dir, _) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        try vault.writeFile(relativePath: path, data: Data(sample.utf8))

        var doc = try parse(vault)
        let task = try #require(doc.sections.flatMap(\.tasks).first { $0.shortPrefix == "CD34" })
        let until = try #require(ActionItemsParser.dayFormatter.date(from: "2026-06-05"))

        try ActionItemsWriter.snooze(task, until: until, fromKind: .urgent, in: path, vault: vault)
        doc = try parse(vault)
        let snoozed = try #require(doc.sections.flatMap(\.tasks).first { $0.shortPrefix == "CD34" })
        #expect(snoozed.snoozedUntil == until)
        #expect(snoozed.snoozedFromKind == .urgent)

        // Re-snoozing replaces the marker instead of stacking a second one.
        let later = try #require(ActionItemsParser.dayFormatter.date(from: "2026-06-09"))
        try ActionItemsWriter.snooze(snoozed, until: later, fromKind: .urgent, in: path, vault: vault)
        let text = String(data: try vault.readFile(relativePath: path), encoding: .utf8)!
        #expect(text.components(separatedBy: "snoozed-until:").count == 2) // one marker
        #expect(text.contains("2026-06-09"))
    }

    @Test func addCommentRoundTrip() throws {
        let (vault, dir, _) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        try vault.writeFile(relativePath: path, data: Data(sample.utf8))

        var doc = try parse(vault)
        let task = try #require(doc.sections.flatMap(\.tasks).first { $0.shortPrefix == "AB12" })

        try ActionItemsWriter.addComment(task, author: "adam", text: "checked this", in: path, vault: vault)
        doc = try parse(vault)
        let after = try #require(doc.sections.flatMap(\.tasks).first { $0.shortPrefix == "AB12" })
        #expect(after.comments.contains { $0.author == "adam" && $0.text == "checked this" })

        // Comment must land under AB12's block, before CD34.
        let text = String(data: try vault.readFile(relativePath: path), encoding: .utf8)!
        let commentIdx = try #require(text.range(of: "- adam: checked this")?.lowerBound)
        let cd34Idx = try #require(text.range(of: "[#CD34]")?.lowerBound)
        #expect(commentIdx < cd34Idx)
    }
}
