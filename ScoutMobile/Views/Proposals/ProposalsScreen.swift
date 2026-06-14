import SwiftUI

/// The Proposals tab: dreaming-generated SKILL.md change proposals from
/// `dreaming-proposals.md`, with Approve / Decline actions on the ones still
/// awaiting a decision and a collapsible archive of resolved ones.
///
/// Approve/Decline only flips the proposal's `**Status:**` line in the file —
/// the next dreaming run is what actually applies the SKILL.md change.
struct ProposalsScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ProposalsScreenContent(store: model.proposals)
    }
}

struct ProposalsScreenContent: View {
    @ObservedObject var store: ProposalsStore
    @State private var resolvedExpanded = false

    var body: some View {
        NavigationStack {
            List {
                content
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Proposals")
            .refreshable { await store.reload() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        case .missing:
            unavailable(
                "No proposals file",
                icon: "tray",
                message: "Dreaming runs write proposals to dreaming-proposals.md when they process feedback."
            )
        case .failed(let err):
            unavailable("Couldn't load proposals", icon: "exclamationmark.triangle", message: err)
        case .loaded:
            loadedContent
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        let awaiting = store.proposals.filter(\.isAwaitingDecision)
        let resolved = store.proposals.filter { !$0.isAwaitingDecision }

        if store.proposals.isEmpty {
            unavailable(
                "No proposals",
                icon: "tray",
                message: "They'll appear here after a dreaming run files one."
            )
        } else {
            Section {
                if awaiting.isEmpty {
                    Text("Nothing awaiting your decision.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(awaiting) { proposal in
                        ProposalCardView(proposal: proposal) { decision in
                            try await store.decide(decision, proposal: proposal)
                        }
                    }
                }
            } header: {
                Text(awaitingHeader(count: awaiting.count))
            }

            if !resolved.isEmpty {
                Section {
                    Button {
                        withAnimation { resolvedExpanded.toggle() }
                    } label: {
                        HStack {
                            Text("Resolved (\(resolved.count))")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: resolvedExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if resolvedExpanded {
                        ForEach(resolved) { proposal in
                            ProposalCardView(proposal: proposal, onDecide: nil)
                        }
                    }
                }
            }
        }
    }

    private func awaitingHeader(count: Int) -> String {
        switch count {
        case 0:  return "Awaiting your decision"
        case 1:  return "1 awaiting your decision"
        default: return "\(count) awaiting your decision"
        }
    }

    @ViewBuilder
    private func unavailable(_ title: String, icon: String, message: String) -> some View {
        Section {
            ContentUnavailableView(title, systemImage: icon, description: Text(message))
        }
    }
}
