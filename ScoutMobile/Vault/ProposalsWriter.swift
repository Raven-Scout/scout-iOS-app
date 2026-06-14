import Foundation

/// A proposal decision the app can write back to the file.
enum ProposalDecision: Sendable, Equatable {
    case approve
    case decline

    /// Leading status word — what a dreaming run keys on.
    var statusWord: String { self == .approve ? "Approved" : "Rejected" }
}

/// Mutates `dreaming-proposals.md` directly (the iOS app has no scoutctl and no
/// git — proposals are plain markdown that dreaming sessions read and write).
///
/// Approve/Decline only flips a proposal's `**Status:**` line; the next dreaming
/// run is what actually applies the SKILL.md change. The edit is line-targeted:
/// locate the section by its exact heading line, replace only the first
/// `**Status:**` line within it, and leave the body, code fences, and every
/// other section byte-for-byte identical. The write goes through
/// `VaultAccess.modifyTextFile` (coordinated read-modify-write) so iCloud /
/// Obsidian writes don't get clobbered — same hygiene as `ActionItemsWriter`.
enum ProposalsWriter {

    enum WriteError: LocalizedError, Equatable {
        /// No section with the given heading line was found in the file.
        case proposalNotFound
        /// The section was found but had no `**Status:**` line to replace.
        case statusLineNotFound

        var errorDescription: String? {
            switch self {
            case .proposalNotFound:
                return "Couldn't find this proposal in the file anymore — it may have been edited elsewhere. Pull to refresh."
            case .statusLineNotFound:
                return "This proposal has no Status line to update."
            }
        }
    }

    /// Apply a decision to `proposal` in the file at `relativePath`.
    static func decide(
        _ decision: ProposalDecision,
        proposal: Proposal,
        in relativePath: String,
        vault: VaultAccess,
        now: Date = Date()
    ) throws {
        let newStatusValue = "\(decision.statusWord) (\(isoDate(now)), via Scout iOS)"
        try vault.modifyTextFile(relativePath: relativePath) { text in
            try rewrite(text: text, headingLine: proposal.headingLine, newStatusValue: newStatusValue)
        }
    }

    // MARK: - Pure rewrite (unit-tested directly)

    /// Replace the `**Status:**` value of the section whose heading line equals
    /// `headingLine`. Only that one line changes — the body, code fences, and
    /// every other section are left byte-for-byte identical. Throws if the
    /// section or its status line cannot be found.
    static func rewrite(text: String, headingLine: String, newStatusValue: String) throws -> String {
        // Preserve the file's trailing-newline shape by splitting on "\n" and
        // rejoining; a trailing "" element round-trips a final newline.
        var lines = text.components(separatedBy: "\n")
        let wantedHeading = headingLine.trimmingCharacters(in: .whitespaces)

        guard let headingIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == wantedHeading
        }) else {
            throw WriteError.proposalNotFound
        }

        // Scan the section body for the first `**Status:**` line.
        var k = headingIndex + 1
        while k < lines.count {
            let line = lines[k]
            if ProposalsParser.isProposalHeading(line) { break }
            if (line.hasPrefix("## ") || line.hasPrefix("# ")) && !line.hasPrefix("### ") { break }
            if ProposalsParser.statusValue(in: line) != nil {
                lines[k] = rebuildStatusLine(original: line, newValue: newStatusValue)
                return lines.joined(separator: "\n")
            }
            k += 1
        }
        throw WriteError.statusLineNotFound
    }

    /// Rebuild a status line, preserving the original leading indentation and
    /// the canonical `**Status:**` label, swapping only the value.
    private static func rebuildStatusLine(original: String, newValue: String) -> String {
        let leadingWhitespace = String(original.prefix(while: { $0 == " " || $0 == "\t" }))
        return "\(leadingWhitespace)**Status:** \(newValue)"
    }

    // MARK: - Helpers

    private static func isoDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }
}
