import SwiftUI

/// One proposal rendered as a card: heading (code + title + status pill),
/// structured body, and — for proposals still awaiting a decision — Approve /
/// Decline actions. Owns its in-flight + error state so a slow or failed write
/// surfaces on the card itself.
struct ProposalCardView: View {
    let proposal: Proposal
    /// Performs the write. Throws so the card can show an inline error.
    /// `nil` for resolved (read-only) proposals.
    var onDecide: (@MainActor (ProposalDecision) async throws -> Void)?

    @State private var inFlight: ProposalDecision?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !proposal.bodyBlocks.isEmpty {
                MarkdownBodyView(blocks: proposal.bodyBlocks)
            }
            if proposal.isAwaitingDecision, onDecide != nil {
                actions
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if !proposal.code.isEmpty {
                    Text(proposal.code)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(proposal.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ProposalStatusPill(status: proposal.status)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 10) {
            actButton("Approve", systemImage: "checkmark", decision: .approve, tint: .green)
            actButton("Decline", systemImage: "xmark", decision: .decline, tint: .secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func actButton(
        _ label: String,
        systemImage: String,
        decision: ProposalDecision,
        tint: Color
    ) -> some View {
        let isBusy = inFlight == decision
        Button {
            decide(decision)
        } label: {
            HStack(spacing: 5) {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
                Text(label)
            }
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .disabled(inFlight != nil)
    }

    private func decide(_ decision: ProposalDecision) {
        guard let onDecide else { return }
        inFlight = decision
        errorText = nil
        Task {
            do {
                try await onDecide(decision)
            } catch {
                errorText = "Couldn't update the file — \(error.localizedDescription)"
            }
            inFlight = nil
        }
    }
}
