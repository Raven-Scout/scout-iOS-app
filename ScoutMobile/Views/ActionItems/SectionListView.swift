import SwiftUI

struct PreambleCard: View {
    let paragraphs: [String]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(visibleParagraphs.enumerated()), id: \.offset) { _, p in
                Text(InlineMarkdown.attributed(p))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if paragraphs.count > 1 {
                Button(expanded ? "Show less" : "Show more") {
                    withAnimation { expanded.toggle() }
                }
                .font(.footnote.weight(.medium))
            }
        }
        .padding(.vertical, 2)
    }

    private var visibleParagraphs: [String] {
        expanded ? paragraphs : Array(paragraphs.prefix(1))
    }
}

struct SectionListView: View {
    let section: ActionSection
    let onToggleDone: (ActionTask) -> Void
    let onSnooze: (ActionTask) -> Void
    let onComment: (ActionTask) -> Void

    /// Section "bullets" include stripped blockquote paragraphs; drop the
    /// leading "> " markers for display and skip empty quote lines.
    private var displayBullets: [(text: String, isQuote: Bool)] {
        section.bullets.compactMap { bullet in
            let isQuote = bullet.hasPrefix(">")
            var text = bullet
            while text.hasPrefix(">") {
                text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            guard !text.isEmpty else { return nil }
            return (text, isQuote)
        }
    }

    var body: some View {
        Section {
            ForEach(section.tasks) { task in
                TaskRowView(
                    task: task,
                    sectionKind: section.kind,
                    onToggleDone: { onToggleDone(task) },
                    onSnooze: { onSnooze(task) },
                    onComment: { onComment(task) }
                )
            }
            ForEach(Array(displayBullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .top, spacing: 8) {
                    Text(bullet.isQuote ? "❝" : "•")
                        .foregroundStyle(.secondary)
                    Text(InlineMarkdown.attributed(bullet.text))
                        .font(.subheadline)
                }
            }
            ForEach(Array(section.tables.enumerated()), id: \.offset) { _, table in
                MarkdownTableView(table: table)
            }
        } header: {
            HStack(spacing: 6) {
                if !section.emoji.isEmpty {
                    Text(section.emoji)
                }
                Text(section.title)
                Spacer()
                if !section.tasks.isEmpty {
                    Text("\(section.tasks.filter { !$0.done }.count) open")
                        .font(.caption2)
                        .foregroundStyle(DS.color(for: section.kind))
                }
            }
        }
    }
}

struct MarkdownTableView: View {
    let table: ActionSection.Table

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { _, h in
                        Text(InlineMarkdown.attributed(h))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            Text(InlineMarkdown.attributed(cell))
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
