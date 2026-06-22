import Testing
import Foundation
@testable import ScoutMobile

@Suite("PerFileItemsWriter (pure)")
struct PerFileItemsWriterPureTests {
    @Test func slugifyLowercasesAndDashes() {
        #expect(PerFileItemsWriter.slugify("Faster Cold Start!") == "faster-cold-start")
        #expect(PerFileItemsWriter.slugify("OAuth/PKCE flow") == "oauth-pkce-flow")
    }

    @Test func slugifyCapsWordCount() {
        #expect(PerFileItemsWriter.slugify("one two three four five", maxWords: 3) == "one-two-three")
    }

    @Test func renderProducesParseableFrontmatter() {
        let text = PerFileItemsWriter.renderItemFile(
            title: "Cache config", status: .open, priority: .high, date: "2026-06-22",
            source: "Slack #scout", area: nil, body: "Some notes.")
        #expect(text.contains("title: \"Cache config\""))
        #expect(text.contains("status: open"))
        #expect(text.contains("priority: high"))
        #expect(text.contains("date: 2026-06-22"))
        #expect(text.contains("source: \"Slack #scout\""))
        #expect(!text.contains("area:"))
        #expect(text.contains("# Cache config"))
        // Round-trips through the parser.
        let item = try! #require(PerFileItemParser.parseFile(contents: text,
                                 relativePath: "docs/wishlist/2026-06-22-cache-config.md"))
        #expect(item.title == "Cache config")
        #expect(item.priority == .high)
        #expect(item.source == "Slack #scout")
    }

    @Test func rewriteFlipsOnlyTheStatusLine() throws {
        let text = """
        ---
        title: "X"
        status: open
        priority: medium
        date: 2026-06-22
        ---

        # X

        Body.
        """
        let out = try PerFileItemsWriter.rewriteFrontmatterStatus(text: text, newStatusValue: "done")
        #expect(out.contains("status: done"))
        #expect(!out.contains("status: open"))
        #expect(out.contains("priority: medium"))  // untouched
        #expect(out.contains("# X"))               // body untouched
    }

    @Test func rewriteThrowsWhenNoFrontmatter() {
        #expect(throws: PerFileItemsWriter.WriteError.self) {
            try PerFileItemsWriter.rewriteFrontmatterStatus(text: "no frontmatter", newStatusValue: "done")
        }
    }
}

@Suite("PerFileItemsWriter end-to-end (coordinated file writes)")
struct PerFileItemsWriterE2ETests {

    private static func fixedDate() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 22; c.hour = 12
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func makeVault() throws -> (vault: VaultAccess, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("perfile-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "perfile-writer-\(UUID().uuidString)"))
        try VaultAccess.saveBookmark(for: dir, defaults: defaults)
        return (VaultAccess(defaults: defaults), dir)
    }

    @Test func addThenResolveRoundTrips() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        let rel = try PerFileItemsWriter.addItem(
            config: .wishlist, title: "Faster cold start", priority: .high,
            body: "Cache the config.", optional: "Slack #scout",
            vault: vault, now: Self.fixedDate())
        #expect(rel == "docs/wishlist/2026-06-22-faster-cold-start.md")

        // Parse the written file: open + high + source captured.
        let text1 = String(data: try vault.readFile(relativePath: rel), encoding: .utf8)!
        let item = try #require(PerFileItemParser.parseFile(contents: text1, relativePath: rel))
        #expect(item.status == .open)
        #expect(item.priority == .high)
        #expect(item.source == "Slack #scout")

        // Resolve to done; reparse reflects it.
        try PerFileItemsWriter.resolve(.done, item: item, vault: vault)
        let text2 = String(data: try vault.readFile(relativePath: rel), encoding: .utf8)!
        let resolved = try #require(PerFileItemParser.parseFile(contents: text2, relativePath: rel))
        #expect(resolved.status == .done)
        #expect(!resolved.isActive)
    }

    @Test func emptyTitleThrows() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: PerFileItemsWriter.WriteError.self) {
            try PerFileItemsWriter.addItem(config: .wishlist, title: "   ", priority: .medium,
                                           body: "", optional: nil, vault: vault, now: Self.fixedDate())
        }
    }
}
