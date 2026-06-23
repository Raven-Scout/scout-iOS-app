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

    @Test func parsesCRLFLineEndings() {
        // Windows / external-editor CRLF: every line ends in \r\n. The parser
        // must still recognize the frontmatter, strip the trailing \r from
        // field values, drop the leading heading, and detect the code fence.
        let crlf = "---\r\ntitle: \"CRLF item\"\r\nstatus: in-progress\r\npriority: high\r\n"
            + "date: 2026-06-21\r\n---\r\n\r\n# CRLF item\r\n\r\nBody line.\r\n\r\n```swift\r\nlet x = 1\r\n```\r\n"
        let item = try! #require(PerFileItemParser.parseFile(
            contents: crlf, relativePath: "docs/wishlist/2026-06-21-crlf-item.md"))
        #expect(item.title == "CRLF item")        // no trailing \r left on the value
        #expect(item.status == .inProgress)        // "in-progress\r" classified correctly
        #expect(item.priority == .high)
        #expect(item.date == "2026-06-21")
        #expect(!item.bodyMarkdown.hasPrefix("# "))  // heading stripped despite \r
        let code = item.bodyBlocks.compactMap { block -> String? in
            if case .code(_, let c) = block { return c } else { return nil }
        }
        #expect(code.count == 1)                   // fence detected despite \r
        #expect(code.first?.contains("let x = 1") == true)
    }

    @Test func unescapesQuotedValuesRoundTrip() {
        // The writer escapes \ and " in quoted frontmatter; the parser must
        // reverse it so titles/sources with those characters round-trip.
        let title = #"He said "hi" \ bye"#
        let rendered = PerFileItemsWriter.renderItemFile(
            title: title, status: .open, priority: .medium, date: "2026-06-22",
            source: #"path\to\"x""#, area: nil, body: "x")
        let item = try! #require(PerFileItemParser.parseFile(
            contents: rendered, relativePath: "docs/wishlist/2026-06-22-x.md"))
        #expect(item.title == title)
        #expect(item.source == #"path\to\"x""#)
    }
}
