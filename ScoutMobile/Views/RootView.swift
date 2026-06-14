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
        // Observe the proposals store directly so the tab badge updates live.
        MainTabContent(proposals: model.proposals)
    }
}

private struct MainTabContent: View {
    @ObservedObject var proposals: ProposalsStore

    var body: some View {
        TabView {
            ActionItemsScreen()
                .tabItem { Label("Today", systemImage: "checklist") }
            ActivityScreen()
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
            ProposalsScreen()
                .tabItem { Label("Proposals", systemImage: "lightbulb") }
                .badge(proposals.pendingCount)
            KnowledgeScreen()
                .tabItem { Label("Knowledge", systemImage: "books.vertical") }
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
