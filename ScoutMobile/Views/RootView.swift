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
        TabView {
            ActionItemsScreen()
                .tabItem { Label("Today", systemImage: "checklist") }
            SessionsScreen()
                .tabItem { Label("Sessions", systemImage: "clock.arrow.circlepath") }
            ScheduleScreen()
                .tabItem { Label("Schedule", systemImage: "calendar") }
            KnowledgeScreen()
                .tabItem { Label("Knowledge", systemImage: "books.vertical") }
            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
