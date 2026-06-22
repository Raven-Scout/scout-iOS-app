import SwiftUI

/// The merged Proposals + Wishlist + Research tab. A segmented control in the
/// navigation bar switches between dreaming proposals (Approve/Decline), the
/// per-file wishlist, and the research queue. Combining the three into one tab
/// keeps the tab bar at five slots — the same pattern `ActivityScreen` uses for
/// Sessions + Schedule. The Wishlist/Research panes contribute their own ＋ Add
/// toolbar button; the Proposals pane contributes none.
struct IdeasScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var pane: Pane = .proposals

    enum Pane: String, CaseIterable {
        case proposals = "Proposals"
        case wishlist = "Wishlist"
        case research = "Research"
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
            }
        }
    }
}
