import SwiftUI

enum TaskStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case open = "Open"
    case done = "Done"
    case snoozed = "Snoozed"
    var id: String { rawValue }
}

/// Thin wrapper that pulls the store out of the environment so the inner
/// view can observe it with @ObservedObject.
struct ActionItemsScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ActionItemsScreenContent(store: model.actionItems)
    }
}

struct ActionItemsScreenContent: View {
    @ObservedObject var store: ActionItemsStore

    @State private var statusFilter: TaskStatusFilter = .all
    @State private var searchText = ""
    @State private var showDatePicker = false
    @State private var snoozeTarget: SnoozeTarget?
    @State private var commentTarget: CommentTarget?
    @State private var writeError: String?

    struct SnoozeTarget: Identifiable {
        let task: ActionTask
        let kind: ActionSection.Kind
        var id: UUID { task.id }
    }
    struct CommentTarget: Identifiable {
        let task: ActionTask
        var id: UUID { task.id }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(store.selectedDate.dayLabel)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .searchable(text: $searchText, prompt: "Search tasks")
                .refreshable { await store.reload() }
                .sheet(isPresented: $showDatePicker) { datePickerSheet }
                .sheet(item: $snoozeTarget) { target in
                    SnoozeSheet(task: target.task) { date in
                        write { try await store.snooze(target.task, until: date, fromKind: target.kind) }
                    }
                    .presentationDetents([.medium])
                }
                .sheet(item: $commentTarget) { target in
                    CommentSheet(task: target.task) { text in
                        write { try await store.addComment(target.task, text: text) }
                    }
                    .presentationDetents([.medium])
                }
                .alert("Couldn't update the file", isPresented: .init(
                    get: { writeError != nil },
                    set: { if !$0 { writeError = nil } }
                )) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(writeError ?? "")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .missing:
            ContentUnavailableView(
                "No briefing for \(store.selectedDate.dayLabel)",
                systemImage: "doc.questionmark",
                description: Text("Scout hasn't produced an action-items file for this date.")
            )
        case .failed(let message):
            ContentUnavailableView(
                "Couldn't load",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .loaded(let doc):
            documentList(doc)
        }
    }

    private func documentList(_ doc: ActionItemsDocument) -> some View {
        List {
            if !doc.preamble.isEmpty && searchText.isEmpty && statusFilter == .all {
                Section {
                    PreambleCard(paragraphs: doc.preamble)
                }
            }
            ForEach(filteredSections(doc)) { section in
                SectionListView(
                    section: section,
                    onToggleDone: { task in
                        write { try await store.setDone(task, done: !task.done) }
                    },
                    onSnooze: { task in
                        snoozeTarget = SnoozeTarget(task: task, kind: task.snoozedFromKind ?? section.kind)
                    },
                    onComment: { task in
                        commentTarget = CommentTarget(task: task)
                    }
                )
            }
        }
        .listStyle(.insetGrouped)
    }

    private func filteredSections(_ doc: ActionItemsDocument) -> [ActionSection] {
        doc.sections.compactMap { section -> ActionSection? in
            let tasks = section.tasks.filter { task in
                switch statusFilter {
                case .all: break
                case .open: if task.done || task.snoozedUntil != nil { return false }
                case .done: if !task.done { return false }
                case .snoozed: if task.snoozedUntil == nil { return false }
                }
                guard !searchText.isEmpty else { return true }
                let haystack = "\(task.plainSubject) \(task.body) \(task.comments.map(\.text).joined(separator: " "))"
                return haystack.localizedCaseInsensitiveContains(searchText)
            }
            // Keep non-task content (bullets/tables) only in unfiltered view.
            let keepExtras = statusFilter == .all && searchText.isEmpty
            if tasks.isEmpty && !(keepExtras && (!section.bullets.isEmpty || !section.tables.isEmpty)) {
                return nil
            }
            return ActionSection(
                id: section.id,
                emoji: section.emoji,
                title: section.title,
                kind: section.kind,
                tasks: tasks,
                bullets: keepExtras ? section.bullets : [],
                tables: keepExtras ? section.tables : [],
                subheads: keepExtras ? section.subheads : []
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                shiftDay(-1)
            } label: {
                // Label (not a bare Image): iOS 26 shrinks the hit target of an
                // Image-only toolbar button, dropping taps near the glyph edge.
                Label("Previous day", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                shiftDay(1)
            } label: {
                Label("Next day", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .disabled(Calendar.current.isDateInToday(store.selectedDate))
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Status", selection: $statusFilter) {
                    ForEach(TaskStatusFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                Button {
                    showDatePicker = true
                } label: {
                    Label("Pick date…", systemImage: "calendar")
                }
            } label: {
                Label("Filter", systemImage: statusFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .labelStyle(.iconOnly)
            }
        }
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "Date",
                selection: Binding(
                    get: { store.selectedDate },
                    set: { store.selectedDate = Calendar.current.startOfDay(for: $0) }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Jump to date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func shiftDay(_ delta: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: delta, to: store.selectedDate) {
            store.selectedDate = newDate
        }
    }

    private func write(_ op: @escaping () async throws -> Void) {
        Task {
            do {
                try await op()
            } catch {
                writeError = error.localizedDescription
            }
        }
    }
}
