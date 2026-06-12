import SwiftUI

struct RunDetailView: View {
    let run: Run
    @ObservedObject var store: SessionsStore

    @State private var logText: String?
    @State private var showFullLog = false

    var body: some View {
        List {
            Section("Summary") {
                row("Type", run.displayName)
                row("Status", run.status.displayName, color: DS.color(for: run.status))
                row("Started", run.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let ended = run.endedAt {
                    row("Finished", ended.formatted(date: .abbreviated, time: .shortened))
                }
                if let d = run.duration {
                    row("Duration", d.compactDuration)
                }
                if let code = run.exitCode {
                    row("Exit code", String(code))
                }
                if let cost = run.cost {
                    row("Cost", "$\(cost)" + (run.budgetCap.map { " / $\($0) cap" } ?? ""))
                }
                row("Log size", ByteCountFormatter.string(fromByteCount: run.logSizeBytes, countStyle: .file))
            }

            if !run.errorsDetected.isEmpty {
                Section("Detected issues (\(run.errorsDetected.count))") {
                    ForEach(Array(run.errorsDetected.prefix(20).enumerated()), id: \.offset) { _, err in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("line \(err.line) · \(err.pattern)")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text(err.snippet)
                                .font(.caption.monospaced())
                                .lineLimit(3)
                        }
                    }
                    if run.errorsDetected.count > 20 {
                        Text("…and \(run.errorsDetected.count - 20) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Log") {
                if let logText {
                    Text(logTail(logText))
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                    Button("View full log") { showFullLog = true }
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle(run.startedAt.shortTime)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            logText = await store.logText(for: run)
        }
        .sheet(isPresented: $showFullLog) {
            NavigationStack {
                ScrollView {
                    Text(logText ?? "")
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Log")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showFullLog = false }
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String, color: Color? = nil) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(color ?? .primary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    /// Last ~40 lines for the inline preview.
    private func logTail(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 40 else { return text }
        return "…\n" + lines.suffix(40).joined(separator: "\n")
    }
}
