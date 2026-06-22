import Foundation

/// Per-pane knobs that parameterize the shared per-file store, list, and writer.
/// Wishlist and Research are two *values* of this type, not two types.
struct PerFileTabConfig: Sendable, Equatable {
    enum OptionalField: Sendable, Equatable {
        case none
        case source(label: String)
        case area(label: String)
        var label: String? {
            switch self {
            case .none: return nil
            case .source(let l), .area(let l): return l
            }
        }
    }

    let title: String
    let priorities: [ItemPriority]
    let defaultPriority: ItemPriority
    let optionalField: OptionalField
    let addNoun: String          // e.g. "wishlist item" — used in Add copy
    let directory: String        // vault-relative directory of item files

    static let wishlist = PerFileTabConfig(
        title: "Wishlist",
        priorities: [.high, .medium, .low],
        defaultPriority: .medium,
        optionalField: .source(label: "Source"),
        addNoun: "wishlist item",
        directory: "docs/wishlist"
    )

    static let research = PerFileTabConfig(
        title: "Research",
        priorities: [.urgent, .high, .medium, .low],
        defaultPriority: .medium,
        optionalField: .area(label: "Area"),
        addNoun: "research topic",
        directory: "knowledge-base/research-queue"
    )
}
