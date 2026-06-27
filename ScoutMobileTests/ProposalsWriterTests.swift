import Testing
import Foundation
@testable import ScoutMobile

private let writerFixture = """
## Proposals

### P-2026-06-13-01 — Add a risk-scoped PR re-resolution step

**Status:** Proposed (awaiting Alex approval)

**Problem.** SKILL.md anchored on one PR.

```bash
gh pr list --repo <repo> --search "<keyword>"
```

### P-2026-06-10-02 — Tighten the budget gate

**Status:** Pending (auto-apply after 2026-06-13)

**Trigger:** repeated overruns.
"""

private let heading1 = "### P-2026-06-13-01 — Add a risk-scoped PR re-resolution step"
private let heading2 = "### P-2026-06-10-02 — Tighten the budget gate"

@Suite("ProposalsWriter.rewrite (pure)")
struct ProposalsWriterRewriteTests {

    @Test func replacesOnlyTheTargetStatusLine() throws {
        let out = try ProposalsWriter.rewrite(
            text: writerFixture,
            headingLine: heading1,
            newStatusValue: "Approved (2026-06-14, via Scout iOS)"
        )
        // Target flipped.
        #expect(out.contains("**Status:** Approved (2026-06-14, via Scout iOS)"))
        // The other proposal's status is untouched.
        #expect(out.contains("**Status:** Pending (auto-apply after 2026-06-13)"))
        // The proposed status is gone (exactly one status changed).
        #expect(!out.contains("**Status:** Proposed (awaiting Alex approval)"))
    }

    @Test func leavesBodyAndCodeFenceByteIdentical() throws {
        let out = try ProposalsWriter.rewrite(
            text: writerFixture,
            headingLine: heading1,
            newStatusValue: "Rejected (2026-06-14, via Scout iOS)"
        )
        #expect(out.contains(#"gh pr list --repo <repo> --search "<keyword>""#))
        #expect(out.contains("**Problem.** SKILL.md anchored on one PR."))
        #expect(out.contains("**Trigger:** repeated overruns."))
    }

    @Test func reparsingTheRewriteReflectsTheNewStatus() throws {
        let out = try ProposalsWriter.rewrite(
            text: writerFixture,
            headingLine: heading2,
            newStatusValue: "Approved (2026-06-14, via Scout iOS)"
        )
        let proposals = ProposalsParser.parse(text: out)
        let target = try #require(proposals.first { $0.headingLine == heading2 })
        #expect(target.status == .approved)
        // The first proposal is still awaiting.
        let other = try #require(proposals.first { $0.headingLine == heading1 })
        #expect(other.status == .proposed)
    }

    @Test func unknownHeadingThrows() {
        #expect(throws: ProposalsWriter.WriteError.self) {
            try ProposalsWriter.rewrite(
                text: writerFixture,
                headingLine: "### P-9999-99-99-99 — Does not exist",
                newStatusValue: "Approved"
            )
        }
    }

    @Test func sectionWithoutStatusLineThrows() {
        let text = """
        ### P-1 — No status here

        Just a body, no status marker.
        """
        #expect(throws: ProposalsWriter.WriteError.self) {
            try ProposalsWriter.rewrite(
                text: text,
                headingLine: "### P-1 — No status here",
                newStatusValue: "Approved"
            )
        }
    }

    @Test func preservesIndentationOnStatusLine() throws {
        let text = "### P-1 — Indented status\n\n  **Status:** Proposed\n"
        let out = try ProposalsWriter.rewrite(
            text: text,
            headingLine: "### P-1 — Indented status",
            newStatusValue: "Approved (x)"
        )
        #expect(out.contains("  **Status:** Approved (x)"))
    }
}

@Suite("ProposalsWriter end-to-end (coordinated file write)")
struct ProposalsWriterE2ETests {

    /// A fixed date so the written status stamp is deterministic: 2026-06-14.
    private static func fixedDate() -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 14; c.hour = 12
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private static let path = "dreaming-proposals.md"

    private func makeVault() throws -> (vault: VaultAccess, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("proposals-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let suiteName = "proposals-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        try VaultAccess.saveBookmark(for: dir, defaults: defaults)
        return (VaultAccess(defaults: defaults), dir)
    }

    private func proposal(_ heading: String, code: String) -> Proposal {
        Proposal(headingLine: heading, code: code, title: "", status: .proposed, bodyMarkdown: "")
    }

    @Test func approveWritesStatusStamp() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        try vault.writeFile(relativePath: Self.path, data: Data(writerFixture.utf8))

        try ProposalsWriter.decide(
            .approve,
            proposal: proposal(heading1, code: "P-2026-06-13-01"),
            in: Self.path,
            vault: vault,
            now: Self.fixedDate()
        )

        let written = String(data: try vault.readFile(relativePath: Self.path), encoding: .utf8)!
        #expect(written.contains("**Status:** Approved (2026-06-14, via Scout iOS)"))
        // The other proposal is untouched.
        #expect(written.contains("**Status:** Pending (auto-apply after 2026-06-13)"))
        // And the body + code fence survive byte-for-byte.
        #expect(written.contains(#"gh pr list --repo <repo> --search "<keyword>""#))

        // Reparsing the file reflects the new status.
        let reparsed = ProposalsParser.parse(text: written)
        #expect(reparsed.first { $0.headingLine == heading1 }?.status == .approved)
    }

    @Test func declineWritesRejectedStatus() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        try vault.writeFile(relativePath: Self.path, data: Data(writerFixture.utf8))

        try ProposalsWriter.decide(
            .decline,
            proposal: proposal(heading2, code: "P-2026-06-10-02"),
            in: Self.path,
            vault: vault,
            now: Self.fixedDate()
        )

        let written = String(data: try vault.readFile(relativePath: Self.path), encoding: .utf8)!
        #expect(written.contains("**Status:** Rejected (2026-06-14, via Scout iOS)"))
        let reparsed = ProposalsParser.parse(text: written)
        #expect(reparsed.first { $0.headingLine == heading2 }?.status == .rejected)
    }

    @Test func unknownHeadingThrowsAndLeavesFileUnchanged() throws {
        let (vault, dir) = try makeVault()
        defer { try? FileManager.default.removeItem(at: dir) }
        try vault.writeFile(relativePath: Self.path, data: Data(writerFixture.utf8))

        #expect(throws: ProposalsWriter.WriteError.self) {
            try ProposalsWriter.decide(
                .approve,
                proposal: proposal("### Nope — missing", code: "X"),
                in: Self.path,
                vault: vault,
                now: Self.fixedDate()
            )
        }
        let written = String(data: try vault.readFile(relativePath: Self.path), encoding: .utf8)!
        #expect(written == writerFixture)
    }
}
