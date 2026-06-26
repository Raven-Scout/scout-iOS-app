import SwiftUI

/// The merged Proposals + Wishlist + Research tab. A segmented control in the
/// navigation bar switches between dreaming proposals (Approve/Decline), the
/// per-file wishlist, and the research queue. Combining the three into one tab
/// keeps the tab bar at five slots — the same pattern `ActivityScreen` uses for
/// Sessions + Schedule, using the same native segmented `Picker`.
///
/// Two non-obvious details, both matching what makes `ActivityScreen` glitch-free:
///
///  - `.navigationDestination(...)` is required. Without a registered destination
///    the `NavigationStack` destructively re-lays-out its `.principal` toolbar
///    item when the content swaps on a pane switch, which collapses the segmented
///    control's segments onto one spot for a frame (visible with three segments;
///    `ActivityScreen`'s two are too short to notice). `ActivityScreen` gets this
///    stability for free from its real `Run` destination; Ideas has no detail
///    navigation, so it registers a no-op one.
///  - The ＋ Add button and its sheet live here, at the same level as the
///    destination — not inside the swapped `PerFileListView`. A toolbar button
///    inside the content that's torn down/rebuilt on each pane switch has its
///    hit-test frame corrupted on first tap (the "needs two taps" bug); keeping
///    it at this stable level, presented via `.sheet(item:)`, avoids that.
struct IdeasScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var pane: Pane = .proposals
    @State private var addingStore: PerFileItemsStore?

    enum Pane: String, CaseIterable {
        case proposals = "Proposals"
        case wishlist = "Wishlist"
        case research = "Research"
    }

    /// The per-file store backing the active pane, or `nil` for Proposals (which
    /// has no ＋ Add affordance).
    private var addableStore: PerFileItemsStore? {
        switch pane {
        case .proposals: return nil
        case .wishlist:  return model.wishlist
        case .research:  return model.research
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch pane {
                case .proposals:
                    ProposalsList(store: model.proposals)
                case .wishlist:
                    PerFileListView(store: model.wishlist)
                case .research:
                    PerFileListView(store: model.research)
                }
            }
            .navigationTitle(pane.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: IdeasNoNavigation.self) { _ in EmptyView() }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $pane) {
                        ForEach(Pane.allCases, id: \.self) { pane in
                            Text(pane.rawValue).tag(pane)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }
                if let store = addableStore {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            addingStore = store
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add \(store.config.addNoun)")
                    }
                }
            }
            .sheet(item: $addingStore) { store in
                AddItemSheet(
                    config: store.config,
                    onSubmit: { title, priority, body, optional in
                        try await store.addItem(title: title, priority: priority, body: body, optional: optional)
                        addingStore = nil
                    },
                    onCancel: { addingStore = nil }
                )
            }
        }
    }
}

/// Uninhabited marker type for `IdeasScreen`'s no-op `navigationDestination`
/// (see `IdeasScreen`). No value is ever created, so the destination never shows.
private struct IdeasNoNavigation: Hashable {}
