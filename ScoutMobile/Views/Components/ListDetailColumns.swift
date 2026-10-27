import SwiftUI

extension View {
    /// Column visibility for the list → detail `NavigationSplitView`s (Activity,
    /// Knowledge) in regular width. Where the split view is wider than tall
    /// (iPhone Duo inner display in its side-bar orientation, a Pro Max in
    /// landscape) both columns tile and stay visible. Where it is taller than
    /// wide (the inner display in portrait) the sidebar can only overlay the
    /// detail, so the list shows until something is picked and then gets out of
    /// the way of the detail. Left to `.automatic`, the portrait case opens on
    /// the empty detail placeholder instead.
    ///
    /// Size classes can't tell the two apart (both are regular × regular), hence
    /// the container's shape. Compact width ignores `visibility` and keeps using
    /// push navigation.
    func listDetailColumns<Selection: Equatable>(
        _ visibility: Binding<NavigationSplitViewVisibility>,
        selection: Selection?
    ) -> some View {
        modifier(ListDetailColumns(visibility: visibility, selection: selection))
    }
}

private struct ListDetailColumns<Selection: Equatable>: ViewModifier {
    @Binding var visibility: NavigationSplitViewVisibility
    let selection: Selection?
    @State private var isTallerThanWide = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Bool.self) { $0.size.height > $0.size.width } action: { tall in
                isTallerThanWide = tall
                update()
            }
            .onChange(of: selection) { _, _ in update() }
            // A NavigationStack in the detail column makes the split view drop to
            // `.detailOnly` as it first appears; re-apply once that has happened.
            .task {
                await Task.yield()
                update()
            }
    }

    private func update() {
        visibility = isTallerThanWide && selection != nil ? .detailOnly : .all
    }
}
