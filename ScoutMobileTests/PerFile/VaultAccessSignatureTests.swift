import Testing
import Foundation
@testable import ScoutMobile

@Suite("VaultAccess.directorySignature")
struct VaultAccessSignatureTests {

    private func makeVault() throws -> (vault: VaultAccess, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-signature-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "vault-signature-\(UUID().uuidString)"))
        try VaultAccess.saveBookmark(for: dir, defaults: defaults)
        return (VaultAccess(defaults: defaults), dir)
    }

    @Test func nilForMissingDirectory() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(vault.directorySignature(relativePath: "docs/wishlist") == nil)
    }

    @Test func stableWhenUnchanged() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try vault.createUniqueFile(inDirectory: "docs/wishlist",
                                       baseName: "2026-06-22-one", contents: "a")
        _ = try vault.createUniqueFile(inDirectory: "docs/wishlist",
                                       baseName: "2026-06-22-two", contents: "bb")

        let first = vault.directorySignature(relativePath: "docs/wishlist")
        let second = vault.directorySignature(relativePath: "docs/wishlist")
        #expect(first != nil)
        #expect(first == second)
    }

    @Test func changesWhenFileAdded() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = try vault.createUniqueFile(inDirectory: "docs/wishlist",
                                       baseName: "2026-06-22-one", contents: "a")
        _ = try vault.createUniqueFile(inDirectory: "docs/wishlist",
                                       baseName: "2026-06-22-two", contents: "bb")
        let before = vault.directorySignature(relativePath: "docs/wishlist")

        _ = try vault.createUniqueFile(inDirectory: "docs/wishlist",
                                       baseName: "2026-06-22-three", contents: "ccc")
        let after = vault.directorySignature(relativePath: "docs/wishlist")

        #expect(before != nil)
        #expect(after != nil)
        #expect(before != after)
    }

    @Test func changesWhenContentRewritten() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        let rel = try vault.createUniqueFile(inDirectory: "docs/wishlist",
                                             baseName: "2026-06-22-one", contents: "short")
        let before = vault.directorySignature(relativePath: "docs/wishlist")

        // Rewrite with a different byte length so `fileSize` differs even if the
        // mtime resolution is too coarse to register — keeps the test deterministic.
        try vault.modifyTextFile(relativePath: rel) { _ in "a much longer body than before" }
        let after = vault.directorySignature(relativePath: "docs/wishlist")

        #expect(before != nil)
        #expect(after != nil)
        #expect(before != after)
    }
}
