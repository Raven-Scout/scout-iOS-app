import SwiftUI

/// Modal sheet for adding a new per-file item (wishlist entry or research
/// topic). Title is required (Add disabled when blank); Priority is a segmented
/// picker from `config.priorities`; the optional Source/Area field appears only
/// when `config.optionalField.label != nil`. Submits via an async `onSubmit`
/// that throws so a failed write keeps the sheet open with an inline error.
struct AddItemSheet: View {
    let config: PerFileTabConfig
    let onSubmit: (String, ItemPriority, String, String?) async throws -> Void
    let onCancel: () -> Void

    @State private var title: String = ""
    @State private var priority: ItemPriority
    @State private var bodyText: String = ""
    @State private var optionalValue: String = ""
    @State private var submitting = false
    @State private var errorText: String?

    init(config: PerFileTabConfig,
         onSubmit: @escaping (String, ItemPriority, String, String?) async throws -> Void,
         onCancel: @escaping () -> Void) {
        self.config = config
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        _priority = State(initialValue: config.defaultPriority)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !submitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("What should Scout do?", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                }
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(config.priorities, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if let label = config.optionalField.label {
                    Section(label) {
                        TextField(label, text: $optionalValue)
                    }
                }
                Section("Notes") {
                    TextField("Optional details", text: $bodyText, axis: .vertical)
                        .lineLimit(4...12)
                }
                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add \(config.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if submitting {
                        ProgressView()
                    } else {
                        Button("Add") { submit() }.disabled(!canSubmit)
                    }
                }
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        errorText = nil
        submitting = true
        let optional = optionalValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                try await onSubmit(title, priority, bodyText, optional.isEmpty ? nil : optional)
                // Success: the presenter dismisses the sheet.
            } catch {
                errorText = error.localizedDescription
            }
            submitting = false
        }
    }
}
