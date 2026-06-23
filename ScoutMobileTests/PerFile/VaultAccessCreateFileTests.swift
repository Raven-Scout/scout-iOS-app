import Testing
import Foundation
@testable import ScoutMobile

@Suite("VaultAccess.createUniqueFile")
struct VaultAccessCreateFileTests {

    private func makeVault() throws -> (vault: VaultAccess, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-createfile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "vault-createfile-\(UUID().uuidString)"))
        try VaultAccess.saveBookmark(for: dir, defaults: defaults)
        return (VaultAccess(defaults: defaults), dir)
    }

    @Test func createsFileAndMissingDirectory() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        let rel = try vault.createUniqueFile(inDirectory: "docs/wishlist",
                                             baseName: "2026-06-22-hello", contents: "hi\n")
        #expect(rel == "docs/wishlist/2026-06-22-hello.md")
        let written = String(data: try vault.readFile(relativePath: rel), encoding: .utf8)
        #expect(written == "hi\n")
    }

    @Test func collisionGetsNumericSuffix() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = try vault.createUniqueFile(inDirectory: "docs/wishlist",
                                               baseName: "2026-06-22-dup", contents: "a")
        let second = try vault.createUniqueFile(inDirectory: "docs/wishlist",
                                                baseName: "2026-06-22-dup", contents: "b")
        #expect(first == "docs/wishlist/2026-06-22-dup.md")
        #expect(second == "docs/wishlist/2026-06-22-dup-2.md")
    }
}
