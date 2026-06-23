import Testing
import Foundation
@testable import ScoutMobile

@Suite("PerFileItem fixture contract")
struct PerFileItemFixtureTests {

    @Test func parsesTheRealWishlistFixture() throws {
        let url = try #require(Bundle(for: PerFileFixtureToken.self)
            .url(forResource: "wishlist-item-example", withExtension: "md"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let item = try #require(PerFileItemParser.parseFile(
            contents: text, relativePath: "docs/wishlist/wishlist-item-example.md"))

        #expect(item.title == "Surface add-write failures in the Add sheet")
        #expect(item.status == .open)
        #expect(item.priority == .high)
        #expect(item.date == "2026-06-19")
        #expect(item.source == "Scout#40 review follow-up")
        #expect(item.isActive)
        // The `# Heading` is stripped; the fenced code block is lifted out verbatim.
        #expect(!item.bodyMarkdown.hasPrefix("# "))
        let code = item.bodyBlocks.compactMap { block -> String? in
            if case .code(_, let c) = block { return c } else { return nil }
        }
        #expect(code.first?.contains("store.addItem(") == true)
    }
}

private final class PerFileFixtureToken {}
