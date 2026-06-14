import SwiftUI

/// The merged Sessions + Schedule tab. A segmented control in the navigation
/// bar switches between the run history ("Sessions") and the configured
/// schedule ("Schedule"). Combining the two former tabs frees a tab slot for
/// Proposals while keeping both views one tap apart.
struct ActivityScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var pane: Pane = .sessions

    enum Pane: String, CaseIterable {
        case sessions = "Sessions"
        case schedule = "Schedule"
    }

    var body: some View {
        NavigationStack {
            Group {
                switch pane {
                case .sessions:
                    SessionsList(store: model.sessions, schedule: model.schedule)
                case .schedule:
                    ScheduleList(store: model.schedule)
                }
            }
            .navigationTitle(pane.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Run.self) { run in
                RunDetailView(run: run, store: model.sessions)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $pane) {
                        ForEach(Pane.allCases, id: \.self) { pane in
                            Text(pane.rawValue).tag(pane)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
            }
        }
    }
}
