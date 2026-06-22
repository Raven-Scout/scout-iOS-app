import Testing
import Foundation
@testable import ScoutMobile

@MainActor
@Suite("PerFileItemsStore")
struct PerFileItemsStoreTests {

    private func makeVault() throws -> (vault: VaultAccess, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("perfile-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "perfile-store-\(UUID().uuidString)"))
        try VaultAccess.saveBookmark(for: dir, defaults: defaults)
        return (VaultAccess(defaults: defaults), dir)
    }

    private func write(_ contents: String, to rel: String, vault: VaultAccess) throws {
        // Ensure the subdirectory exists, then write.
        _ = try vault.createUniqueFile(inDirectory: (rel as NSString).deletingLastPathComponent,
                                       baseName: ((rel as NSString).lastPathComponent as NSString).deletingPathExtension,
                                       contents: contents)
    }

    @Test func missingDirectoryReportsMissing() async throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PerFileItemsStore(vault: vault, config: .wishlist)
        await store.reload()
        #expect(store.state == .missing)
        #expect(store.items.isEmpty)
    }

    @Test func loadsParsesAndCountsActive() async throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        let open = """
        ---
        title: "Open one"
        status: open
        priority: high
        date: 2026-06-20
        ---

        # Open one

        Body.
        """
        let done = """
        ---
        title: "Done one"
        status: done
        priority: low
        date: 2026-06-19
        ---

        # Done one

        Body.
        """
        try write(open, to: "docs/wishlist/2026-06-20-open-one.md", vault: vault)
        try write(done, to: "docs/wishlist/2026-06-19-done-one.md", vault: vault)
        // A non-item file with no frontmatter must be skipped.
        try write("# Readme\n\nnot an item", to: "docs/wishlist/readme.md", vault: vault)

        let store = PerFileItemsStore(vault: vault, config: .wishlist)
        await store.reload()

        #expect(store.state == .loaded)
        #expect(store.items.count == 2)               // readme skipped
        #expect(store.activeCount == 1)               // only the open one
        // Newest-first by filename: 2026-06-20 before 2026-06-19.
        #expect(store.items.first?.title == "Open one")
    }

    @Test func addThenResolveUpdatesPublishedItems() async throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = PerFileItemsStore(vault: vault, config: .wishlist)

        try await store.addItem(title: "New idea", priority: .high, body: "Notes.", optional: "Slack")
        #expect(store.items.count == 1)
        #expect(store.activeCount == 1)

        let item = try #require(store.items.first)
        try await store.resolve(.done, item: item)
        #expect(store.activeCount == 0)
        #expect(store.items.first?.status == .done)
    }

    @Test func reloadIfChangedSkipsWhenUnchangedAndPicksUpChanges() async throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        let one = """
        ---
        title: "First"
        status: open
        priority: high
        date: 2026-06-20
        ---

        # First

        Body.
        """
        try write(one, to: "docs/wishlist/2026-06-20-first.md", vault: vault)

        let store = PerFileItemsStore(vault: vault, config: .wishlist)
        await store.reload()
        #expect(store.state == .loaded)
        #expect(store.items.count == 1)
        let firstId = try #require(store.items.first?.id)

        // No change on disk → fast-path skips the reparse; items stay identical.
        await store.reloadIfChanged()
        #expect(store.items.count == 1)
        #expect(store.items.first?.id == firstId)

        // External add → the signature flips and the new item shows up.
        let two = """
        ---
        title: "Second"
        status: open
        priority: medium
        date: 2026-06-21
        ---

        # Second

        Body.
        """
        try write(two, to: "docs/wishlist/2026-06-21-second.md", vault: vault)
        await store.reloadIfChanged()
        #expect(store.items.count == 2)
    }
}
