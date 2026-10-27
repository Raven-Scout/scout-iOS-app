import SwiftUI

/// The merged Sessions + Schedule tab. A segmented control in the navigation
/// bar switches between the run history ("Sessions") and the configured
/// schedule ("Schedule"). Combining the two former tabs frees a tab slot for
/// Proposals while keeping both views one tap apart.
///
/// Built as a two-column `NavigationSplitView` (list → run detail) so the
/// iPhone Duo inner display (regular width) shows the run history and the
/// selected run side by side, Mail-style, as the HIG asks for an extra level of
/// hierarchy on the larger display. In compact width (outer display, every
/// other iPhone in portrait) the split view collapses into the same push
/// navigation the tab always had. Selection is by `Run.ID`, not `Run`, so the
/// highlight and the detail survive the 60 s reload rewriting a running run.
struct ActivityScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var pane: Pane = .sessions
    @State private var selectedRunID: Run.ID?
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    enum Pane: String, CaseIterable {
        case sessions = "Sessions"
        case schedule = "Schedule"
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            Group {
                switch pane {
                case .sessions:
                    SessionsList(store: model.sessions, schedule: model.schedule, selection: $selectedRunID)
                case .schedule:
                    ScheduleList(store: model.schedule)
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
                    .frame(maxWidth: 240)
                }
            }
        } detail: {
            RunDetailColumn(store: model.sessions, runID: selectedRunID)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

/// Detail column of `ActivityScreen`: the selected run, re-resolved from the
/// store on every reload so a running run's status stays current.
private struct RunDetailColumn: View {
    @ObservedObject var store: SessionsStore
    let runID: Run.ID?

    var body: some View {
        if let run = store.runs.first(where: { $0.id == runID }) {
            RunDetailView(run: run, store: store)
                // New identity per run: resets the loaded log and re-runs `.task`.
                .id(run.id)
        } else {
            ContentUnavailableView(
                "No session selected",
                systemImage: "clock.arrow.circlepath",
                description: Text("Pick a run from the list to see its summary and log.")
            )
        }
    }
}
