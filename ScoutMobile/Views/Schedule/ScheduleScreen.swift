import SwiftUI

/// Schedule list content — upcoming fires plus the configured slots. Hosted
/// inside `ActivityScreen`'s shared `NavigationStack`, so it carries no
/// navigation chrome of its own.
struct ScheduleList: View {
    @ObservedObject var store: ScheduleStore
    @State private var typeFilter: SlotType?

    var body: some View {
        List {
            if !store.upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(store.upcoming.prefix(5)) { up in
                        HStack(spacing: 10) {
                            Image(systemName: DS.icon(for: up.type))
                                .foregroundStyle(DS.color(for: up.type))
                                .frame(width: 24)
                            Text(up.slotKey)
                                .font(.subheadline)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(up.scheduledAt.dayLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(up.scheduledAt.shortTime)
                                    .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                }
            }

            Section {
                if filteredSlots.isEmpty {
                    ContentUnavailableView(
                        "No schedule",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text(store.lastError ?? "No slots found in .scout-state/schedule.yaml.")
                    )
                }
                ForEach(filteredSlots) { slot in
                    SlotRowView(slot: slot)
                }
            } header: {
                HStack {
                    Text("Slots")
                    Spacer()
                    Menu {
                        Button("All types") { typeFilter = nil }
                        ForEach(SlotType.allCases, id: \.self) { t in
                            Button(t.displayName) { typeFilter = t }
                        }
                    } label: {
                        Text(typeFilter?.displayName ?? "All")
                            .font(.caption)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await store.reload() }
    }

    private var filteredSlots: [Slot] {
        guard let typeFilter else { return store.slots }
        return store.slots.filter { $0.type == typeFilter }
    }
}

struct SlotRowView: View {
    let slot: Slot

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(DS.color(for: slot.type))
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(slot.key)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 6) {
                    Text(slot.type.displayName)
                        .foregroundStyle(DS.color(for: slot.type))
                    Text("·")
                    Text(weekdaysLabel)
                    if let budget = slot.budgetUsd {
                        Text("·")
                        Text("$\(budget, specifier: "%.0f")")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(slot.firesAtLocal)
                    .font(.title3.monospacedDigit())
                Text(slot.onMiss.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var weekdaysLabel: String {
        let weekday = Set(slot.weekdays)
        if weekday == ["Mon", "Tue", "Wed", "Thu", "Fri"] { return "Weekdays" }
        if weekday == ["Sat", "Sun"] { return "Weekends" }
        if weekday.count == 7 { return "Every day" }
        return slot.weekdays.joined(separator: " ")
    }
}
