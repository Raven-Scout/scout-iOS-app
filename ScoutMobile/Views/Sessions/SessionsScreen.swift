import SwiftUI

/// Sessions list content — the run history plus an "Up next" row. Hosted
/// inside `ActivityScreen`'s shared `NavigationStack`, so it carries no
/// navigation chrome of its own (the `Run` destination lives on the parent).
struct SessionsList: View {
    @ObservedObject var store: SessionsStore
    @ObservedObject var schedule: ScheduleStore

    var body: some View {
        List {
            if let next = schedule.upcoming.first {
                Section("Up next") {
                    HStack(spacing: 10) {
                        Image(systemName: DS.icon(for: next.type))
                            .foregroundStyle(DS.color(for: next.type))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(next.slotKey)
                                .font(.subheadline.weight(.medium))
                            Text(next.scheduledAt, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(next.scheduledAt.shortTime)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if store.runs.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(store.lastError ?? "Runs appear here once Scout writes logs into .scout-logs/.")
                )
            } else {
                ForEach(groupedRuns, id: \.day) { group in
                    Section(group.day.dayLabel) {
                        ForEach(group.runs) { run in
                            NavigationLink(value: run) {
                                RunRowView(run: run)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.reload() }
    }

    private var groupedRuns: [(day: Date, runs: [Run])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: store.runs) { cal.startOfDay(for: $0.startedAt) }
        return groups.keys.sorted(by: >).map { (day: $0, runs: groups[$0] ?? []) }
    }
}

struct RunRowView: View {
    let run: Run

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: DS.icon(for: run.status))
                .foregroundStyle(DS.color(for: run.status))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(run.displayName)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    Text(run.startedAt.shortTime)
                    if let d = run.duration {
                        Text("·")
                        Text(d.compactDuration)
                    }
                    if !run.errorsDetected.isEmpty {
                        Text("·")
                        Label("\(run.errorsDetected.count)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(run.status.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(DS.color(for: run.status))
                if let cost = run.cost, cost > 0 {
                    Text(verbatim: "$\(cost)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
