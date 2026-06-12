import SwiftUI

struct KnowledgeScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            KnowledgeFolderView(store: model.knowledge, relativePath: "", title: "Knowledge")
                .navigationDestination(for: KnowledgeBaseStore.Entry.self) { entry in
                    if entry.isDirectory {
                        KnowledgeFolderView(store: model.knowledge, relativePath: entry.relativePath, title: entry.name)
                    } else {
                        MarkdownFileView(store: model.knowledge, relativePath: entry.relativePath, title: entry.name)
                    }
                }
                .navigationDestination(for: String.self) { wikiPath in
                    MarkdownFileView(
                        store: model.knowledge,
                        relativePath: wikiPath,
                        title: URL(fileURLWithPath: wikiPath).deletingPathExtension().lastPathComponent
                    )
                }
        }
    }
}

struct KnowledgeFolderView: View {
    @ObservedObject var store: KnowledgeBaseStore
    let relativePath: String
    let title: String

    var body: some View {
        List {
            let entries = store.entriesByPath[relativePath] ?? []
            if entries.isEmpty {
                ContentUnavailableView(
                    "Nothing here",
                    systemImage: "folder",
                    description: Text(store.lastError ?? "No markdown files in this folder.")
                )
            }
            ForEach(entries) { entry in
                NavigationLink(value: entry) {
                    HStack(spacing: 10) {
                        Image(systemName: entry.isDirectory ? "folder" : "doc.text")
                            .foregroundStyle(entry.isDirectory ? Color.accentColor : .secondary)
                            .frame(width: 24)
                        Text(entry.isDirectory ? entry.name : String(entry.name.dropLast(3)))
                            .font(.subheadline)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: relativePath) {
            await store.loadEntries(at: relativePath)
        }
        .refreshable {
            await store.loadEntries(at: relativePath)
        }
    }
}

struct MarkdownFileView: View {
    @ObservedObject var store: KnowledgeBaseStore
    let relativePath: String
    let title: String

    @State private var text: String?
    @State private var navigateTo: String?

    var body: some View {
        Group {
            if let text {
                ScrollView {
                    MarkdownDocumentView(text: text) { wikiTarget in
                        Task {
                            if let resolved = await store.resolveWikilink(wikiTarget) {
                                navigateTo = resolved
                            }
                        }
                    }
                    .padding()
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $navigateTo) { path in
            MarkdownFileView(
                store: store,
                relativePath: path,
                title: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            )
        }
        .task(id: relativePath) {
            text = await store.readMarkdown(relativePath: relativePath)
        }
    }
}

/// Block-level markdown renderer: headings, bullets, quotes, code fences,
/// tables and paragraphs — enough for Scout's KB files. Inline styling is
/// delegated to AttributedString markdown; `[[wikilinks]]` become tappable
/// scoutwiki:// links handled via the openURL environment.
struct MarkdownDocumentView: View {
    let text: String
    let onWikilink: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "scoutwiki" {
                let target = url.absoluteString
                    .replacingOccurrences(of: "scoutwiki://", with: "")
                    .removingPercentEncoding ?? ""
                onWikilink(target)
                return .handled
            }
            return .systemAction
        })
    }

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(level: Int, text: String)
        case quote(String)
        case code(String)
        case rule
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var inCode = false
        var codeLines: [String] = []
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                out.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if inCode {
                    out.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                }
                inCode.toggle()
                continue
            }
            if inCode {
                codeLines.append(line)
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { flushParagraph(); continue }
            if trimmed == "---" || trimmed == "***" { flushParagraph(); out.append(.rule); continue }
            if let level = headingLevel(line) {
                flushParagraph()
                out.append(.heading(level: level, text: String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                out.append(.quote(String(trimmed.dropFirst(2))))
                continue
            }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
                out.append(.bullet(level: ActionItemsParser.indentLevelFor(String(indent)), text: String(trimmed.dropFirst(2))))
                continue
            }
            paragraph.append(trimmed)
        }
        flushParagraph()
        if inCode && !codeLines.isEmpty {
            out.append(.code(codeLines.joined(separator: "\n")))
        }
        return out
    }

    private func headingLevel(_ line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard hashes <= 6, line.dropFirst(hashes).hasPrefix(" ") else { return nil }
        return hashes
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(InlineMarkdown.attributed(text, wikilinksTappable: true))
                .font(headingFont(level))
                .padding(.top, level <= 2 ? 6 : 2)
        case .paragraph(let text):
            Text(InlineMarkdown.attributed(text, wikilinksTappable: true))
                .font(.subheadline)
        case .bullet(let level, let text):
            HStack(alignment: .top, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(InlineMarkdown.attributed(text, wikilinksTappable: true))
                    .font(.subheadline)
            }
            .padding(.leading, CGFloat(level) * 16)
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(width: 3)
                Text(InlineMarkdown.attributed(text, wikilinksTappable: true))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.caption.monospaced())
                    .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
        case .rule:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2.bold()
        case 2: return .title3.bold()
        case 3: return .headline
        default: return .subheadline.bold()
        }
    }
}
