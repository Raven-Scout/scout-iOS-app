import Foundation

/// One per-file Wishlist/Research item: YAML frontmatter + markdown body.
///
/// Identity is the vault-relative path — both the stable SwiftUI id and the
/// file the writer rewrites on resolve. (iOS resolves the security-scoped vault
/// root per operation, so we never hold an absolute URL the way desktop does.)
struct PerFileItem: Identifiable, Equatable, Sendable {
    let relativePath: String
    let date: String          // frontmatter `date:` or filename YYYY-MM-DD prefix
    let title: String         // frontmatter `title:` or filename stem
    let status: ItemStatus
    let priority: ItemPriority
    let source: String?       // wishlist provenance (optional)
    let area: String?         // research grouping (optional)
    let bodyMarkdown: String

    var id: String { relativePath }
    var isActive: Bool { status.isActive }
    var bodyBlocks: [MarkdownBodyBlock] { MarkdownBodyBlock.blocks(from: bodyMarkdown) }
}
