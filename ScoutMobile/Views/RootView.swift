import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.hasVault {
            MainTabView()
                .onAppear { model.startStores() }
        } else {
            OnboardingView()
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // Observe the three Ideas stores directly so the tab badge updates live.
        MainTabContent(proposals: model.proposals, wishlist: model.wishlist, research: model.research)
    }
}

private struct MainTabContent: View {
    @ObservedObject var proposals: ProposalsStore
    @ObservedObject var wishlist: PerFileItemsStore
    @ObservedObject var research: PerFileItemsStore

    /// Everything across the Ideas tab still awaiting you: proposals needing a
    /// decision plus active (open/in-progress) wishlist and research items.
    private var ideasBadge: Int {
        proposals.pendingCount + wishlist.activeCount + research.activeCount
    }

    var body: some View {
        TabView {
            ActionItemsScreen()
                .tabItem { Label("Today", systemImage: "checklist") }
            ActivityScreen()
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
            IdeasScreen()
                .tabItem { Label("Ideas", systemImage: "lightbulb") }
                .badge(ideasBadge)
            KnowledgeScreen()
                .tabItem { Label("Knowledge", systemImage: "books.vertical") }
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
