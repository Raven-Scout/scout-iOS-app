import Testing
@testable import ScoutMobile

@Suite("PerFileItemParser")
struct PerFileItemParserTests {

    private let wishlistFixture = """
    ---
    title: "Faster cold start"
    status: open
    priority: high
    date: 2026-06-20
    source: "Slack #scout"
    ---

    # Faster cold start

    Cache the parsed config between launches.

    ```swift
    let cached = try Cache.load()
    ```
    """

    @Test func parsesFrontmatterAndBody() {
        let item = PerFileItemParser.parseFile(contents: wishlistFixture,
                                               relativePath: "docs/wishlist/2026-06-20-faster-cold-start.md")
        let unwrapped = try! #require(item)
        #expect(unwrapped.title == "Faster cold start")
        #expect(unwrapped.status == .open)
        #expect(unwrapped.priority == .high)
        #expect(unwrapped.date == "2026-06-20")
        #expect(unwrapped.source == "Slack #scout")
        #expect(unwrapped.area == nil)
        #expect(unwrapped.relativePath == "docs/wishlist/2026-06-20-faster-cold-start.md")
        // The leading `# Heading` is stripped; prose + code survive.
        #expect(!unwrapped.bodyMarkdown.hasPrefix("# "))
        #expect(unwrapped.bodyMarkdown.contains("Cache the parsed config"))
        let codeBlocks = unwrapped.bodyBlocks.compactMap { block -> String? in
            if case .code(_, let c) = block { return c } else { return nil }
        }
        #expect(codeBlocks.first == "let cached = try Cache.load()")
    }

    @Test func noFrontmatterYieldsNil() {
        #expect(PerFileItemParser.parseFile(contents: "# Just a doc\n\nNo frontmatter here.",
                                            relativePath: "docs/wishlist/readme.md") == nil)
    }

    @Test func fallsBackToFilenameForDateAndTitle() {
        let text = """
        ---
        status: in-progress
        priority: bogus
        ---

        Body only.
        """
        let item = try! #require(PerFileItemParser.parseFile(
            contents: text, relativePath: "knowledge-base/research-queue/2026-06-19-oauth-pkce.md"))
        #expect(item.date == "2026-06-19")            // from filename prefix
        #expect(item.title == "2026-06-19-oauth-pkce") // from filename stem
        #expect(item.status == .inProgress)
        #expect(item.priority == .medium)             // unrecognized → medium
    }

    @Test func readsAreaForResearchItems() {
        let text = """
        ---
        title: "PKCE flow"
        status: open
        priority: urgent
        date: 2026-06-19
        area: "Auth"
        ---

        # PKCE flow

        Investigate.
        """
        let item = try! #require(PerFileItemParser.parseFile(
            contents: text, relativePath: "knowledge-base/research-queue/2026-06-19-pkce-flow.md"))
        #expect(item.area == "Auth")
        #expect(item.source == nil)
        #expect(item.priority == .urgent)
        #expect(item.isActive)
    }
}
