import SwiftUI

struct TaskRowView: View {
    let task: ActionTask
    let sectionKind: ActionSection.Kind
    let onToggleDone: () -> Void
    let onSnooze: () -> Void
    let onComment: () -> Void

    @EnvironmentObject private var settings: AppSettings
    @State private var expanded = false

    private var effectiveKind: ActionSection.Kind {
        task.snoozedFromKind ?? sectionKind
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onToggleDone) {
                    Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.done ? .green : DS.color(for: effectiveKind))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(InlineMarkdown.attributed(task.subject))
                        .font(.subheadline)
                        .strikethrough(task.done)
                        .foregroundStyle(task.done ? .secondary : .primary)
                        .lineLimit(expanded ? nil : 3)

                    badgeRow

                    if expanded {
                        expandedDetail
                    }
                }
            }
        }
        .padding(.leading, CGFloat(task.indentLevel) * 16)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy) { expanded.toggle() }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onToggleDone()
            } label: {
                Label(task.done ? "Reopen" : "Done", systemImage: task.done ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(task.done ? .orange : .green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                onSnooze()
            } label: {
                Label("Snooze", systemImage: "moon.zzz")
            }
            .tint(.indigo)
            Button {
                onComment()
            } label: {
                Label("Comment", systemImage: "text.bubble")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button(task.done ? "Reopen" : "Mark done", systemImage: task.done ? "arrow.uturn.backward" : "checkmark") {
                onToggleDone()
            }
            Button("Snooze…", systemImage: "moon.zzz") { onSnooze() }
            Button("Add comment…", systemImage: "text.bubble") { onComment() }
        }
    }

    @ViewBuilder
    private var badgeRow: some View {
        let hasBadges = task.shortPrefix != nil || task.snoozedUntil != nil
            || task.carriedInFrom != nil || !task.deepLinks.isEmpty || !task.comments.isEmpty
        if hasBadges {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let prefix = task.shortPrefix {
                        BadgeView(text: "#\(prefix)", color: .secondary)
                    }
                    if let snoozed = task.snoozedUntil {
                        BadgeView(text: "🛌 until \(snoozed.formatted(.dateTime.day().month(.abbreviated)))", color: .indigo)
                    }
                    if let carried = task.carriedInFrom {
                        BadgeView(text: "↩︎ from \(carried.formatted(.dateTime.day().month(.abbreviated)))", color: .secondary)
                    }
                    if !task.comments.isEmpty {
                        BadgeView(text: "💬 \(task.comments.count)", color: .blue)
                    }
                    ForEach(task.deepLinks) { link in
                        Button {
                            LinkOpener.open(link, linearWorkspace: settings.linearWorkspace)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: link.systemImage)
                                    .font(.caption2)
                                Text(link.displayLabel)
                            }
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                            .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var expandedDetail: some View {
        let blocks = TaskBodyParser.blocks(from: task.body)
        if !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    TaskBodyBlockView(block: block)
                }
            }
            .padding(.top, 2)
        }
        if !task.comments.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(task.comments.enumerated()), id: \.offset) { _, comment in
                    HStack(alignment: .top, spacing: 6) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.4))
                            .frame(width: 2)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(comment.author).font(.caption2.bold())
                                if !comment.timestamp.isEmpty {
                                    Text(comment.timestamp).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Text(InlineMarkdown.attributed(comment.text))
                                .font(.caption)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}

struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.12)))
            .foregroundStyle(color)
    }
}

struct TaskBodyBlockView: View {
    let block: TaskBodyBlock
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        switch block {
        case .paragraph(let label, let text):
            VStack(alignment: .leading, spacing: 2) {
                if let label {
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                if !text.isEmpty {
                    Text(InlineMarkdown.attributed(text))
                        .font(.caption)
                        .foregroundStyle(.primary.opacity(0.85))
                }
            }
        case .steps(let label, let items):
            VStack(alignment: .leading, spacing: 3) {
                if let label {
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(idx + 1).")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(InlineMarkdown.attributed(item))
                            .font(.caption)
                    }
                }
            }
        case .links(let targets):
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                        BadgeView(text: "[[\(target)]]", color: .purple)
                    }
                }
            }
        }
    }
}
