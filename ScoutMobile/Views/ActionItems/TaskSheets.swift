import SwiftUI

struct SnoozeSheet: View {
    let task: ActionTask
    let onConfirm: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(task.plainSubject)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    QuickSnoozeButton(label: "Tomorrow", days: 1, date: $date)
                    QuickSnoozeButton(label: "+3 days", days: 3, date: $date)
                    QuickSnoozeButton(label: "Next week", days: 7, date: $date)
                }

                DatePicker("Snooze until", selection: $date, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.compact)

                Spacer()
            }
            .padding()
            .navigationTitle("Snooze")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Snooze") {
                        onConfirm(date)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct QuickSnoozeButton: View {
    let label: String
    let days: Int
    @Binding var date: Date

    var body: some View {
        Button(label) {
            date = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: Date())) ?? date
        }
        .buttonStyle(.bordered)
        .font(.footnote)
    }
}

struct CommentSheet: View {
    let task: ActionTask
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(task.plainSubject)
                    .font(.subheadline)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)

                TextField("Your comment", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)

                Spacer()
            }
            .padding()
            .navigationTitle("Add comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onConfirm(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}
