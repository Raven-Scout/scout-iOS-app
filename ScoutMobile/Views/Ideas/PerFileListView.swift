import SwiftUI

/// The Wishlist / Research pane: active items (priority-sorted) with Done/Drop,
/// and a collapsible Resolved archive. Hosted inside `IdeasScreen`'s shared
/// `NavigationStack`, it carries no navigation chrome of its own — the ＋ Add
/// button and its sheet are owned by `IdeasScreen` (keeping the toolbar button at
/// a stable level so it isn't re-created on pane switches, which otherwise makes
/// it need two taps).
struct PerFileListView: View {
    @ObservedObject var store: PerFileItemsStore

    @State private var resolvedExpanded = false

    var body: some View {
        List {
            content
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.reload() }
        .task { await store.reloadIfChanged() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            Section {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        case .missing:
            unavailable(
                "No \(store.config.title.lowercased()) yet",
                icon: "tray",
                message: "Items appear here once a Scout run writes them. Tap ＋ to add one now."
            )
        case .failed(let err):
            unavailable("Couldn't load \(store.config.title.lowercased())",
                        icon: "exclamationmark.triangle", message: err)
        case .loaded:
            loadedContent
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        let awaiting = store.items.filter(\.isActive).sorted { $0.priority < $1.priority }
        let resolved = store.items.filter { !$0.isActive }

        if store.items.isEmpty {
            unavailable(
                "Nothing here yet",
                icon: "sparkles",
                message: "Tap ＋ to add a \(store.config.addNoun)."
            )
        } else {
            Section {
                if awaiting.isEmpty {
                    Text("Nothing active right now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(awaiting) { item in
                        PerFileItemCardView(item: item, optionalLabel: store.config.optionalField.label) { resolution in
                            try await store.resolve(resolution, item: item)
                        }
                    }
                }
            } header: {
                Text(activeHeader(count: awaiting.count))
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
                        ForEach(resolved) { item in
                            PerFileItemCardView(item: item, optionalLabel: store.config.optionalField.label, onResolve: nil)
                        }
                    }
                }
            }
        }
    }

    private func activeHeader(count: Int) -> String {
        switch count {
        case 0:  return "Active"
        case 1:  return "1 active"
        default: return "\(count) active"
        }
    }

    @ViewBuilder
    private func unavailable(_ title: String, icon: String, message: String) -> some View {
        Section {
            ContentUnavailableView(title, systemImage: icon, description: Text(message))
        }
    }
}
