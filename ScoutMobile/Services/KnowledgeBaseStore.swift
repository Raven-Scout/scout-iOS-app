import Foundation
import Combine

/// Browses the vault's markdown content (knowledge-base/, docs/, top-level
/// .md files). Read-only.
@MainActor
final class KnowledgeBaseStore: ObservableObject {

    struct Entry: Identifiable, Hashable {
        let name: String
        let relativePath: String
        let isDirectory: Bool
        var id: String { relativePath }
    }

    @Published private(set) var entriesByPath: [String: [Entry]] = [:]
    @Published private(set) var lastError: String?

    private let vault: VaultAccess

    init(vault: VaultAccess) {
        self.vault = vault
    }

    /// Roots shown on the Knowledge tab.
    static let hiddenPrefixes: Set<String> = [".git", ".obsidian", ".scout-cache"]

    func loadEntries(at relativePath: String) async {
        let vault = self.vault
        let result = await vault.performIO { () -> Result<[Entry], Error> in
            do {
                let names = try vault.listDirectory(relativePath: relativePath)
                var out: [Entry] = []
                for name in names {
                    if name.hasPrefix(".") && relativePath.isEmpty { continue }
                    let rel = relativePath.isEmpty ? name : "\(relativePath)/\(name)"
                    var isDir = ObjCBool(false)
                    let exists = (try? vault.withVault { root -> Bool in
                        FileManager.default.fileExists(atPath: root.appendingPathComponent(rel).path, isDirectory: &isDir)
                    }) ?? false
                    if exists && isDir.boolValue {
                        out.append(Entry(name: name, relativePath: rel, isDirectory: true))
                    } else if name.hasSuffix(".md") {
                        out.append(Entry(name: name, relativePath: rel, isDirectory: false))
                    }
                }
                // Directories first, then files, alphabetical.
                out.sort { a, b in
                    if a.isDirectory != b.isDirectory { return a.isDirectory }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
                return .success(out)
            } catch {
                return .failure(error)
            }
        }
        switch result {
        case .success(let entries):
            entriesByPath[relativePath] = entries
            lastError = nil
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    func readMarkdown(relativePath: String) async -> String? {
        let vault = self.vault
        return await vault.performIO { () -> String? in
            guard let data = vault.readFileIfExists(relativePath: relativePath) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    /// Resolve a `[[wikilink]]` target to a vault-relative markdown path by
    /// searching known directories (Obsidian-style shortest-path resolution,
    /// simplified: exact filename match anywhere under knowledge-base/).
    func resolveWikilink(_ target: String) async -> String? {
        let vault = self.vault
        let fileName = target.hasSuffix(".md") ? target : "\(target).md"
        return await vault.performIO { () -> String? in
            Self.findFile(named: fileName, under: "knowledge-base", vault: vault, depth: 3)
                ?? Self.findFile(named: fileName, under: "", vault: vault, depth: 1)
        }
    }

    nonisolated private static func findFile(named fileName: String, under dir: String, vault: VaultAccess, depth: Int) -> String? {
        guard depth >= 0, let names = try? vault.listDirectory(relativePath: dir) else { return nil }
        for name in names {
            if name.hasPrefix(".") { continue }
            let rel = dir.isEmpty ? name : "\(dir)/\(name)"
            if name.caseInsensitiveCompare(fileName) == .orderedSame { return rel }
        }
        guard depth > 0 else { return nil }
        for name in names {
            if name.hasPrefix(".") || name.contains(".") { continue }
            let rel = dir.isEmpty ? name : "\(dir)/\(name)"
            if let found = findFile(named: fileName, under: rel, vault: vault, depth: depth - 1) {
                return found
            }
        }
        return nil
    }
}
