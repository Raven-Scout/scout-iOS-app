import Foundation
import Combine

/// Loads + watches the daily action-items document for a selected date.
/// iOS has no FSEvents on security-scoped external folders, so refresh is
/// polling-based: on foreground, on demand (pull-to-refresh), and a timer.
@MainActor
final class ActionItemsStore: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case loaded(ActionItemsDocument)
        case missing          // no file for the selected date
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var selectedDate: Date {
        didSet {
            if !Calendar.current.isDate(selectedDate, inSameDayAs: oldValue) {
                Task { await reload() }
            }
        }
    }
    /// Dates that have an action-items file, for the date picker.
    @Published private(set) var availableDates: [Date] = []

    private let vault: VaultAccess
    private let settings: AppSettings
    private var refreshTimer: Timer?

    init(vault: VaultAccess, settings: AppSettings) {
        self.vault = vault
        self.settings = settings
        self.selectedDate = Calendar.current.startOfDay(for: Date())
    }

    var selectedRelativePath: String {
        "action-items/action-items-\(ActionItemsParser.dayFormatter.string(from: selectedDate)).md"
    }

    func start() {
        Task { await reload() }
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.reloadIfChanged() }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func reload() async {
        if case .idle = state { state = .loading }
        let path = selectedRelativePath
        let vault = self.vault
        let author = settings.authorName
        let result: State = await vault.performIO {
            Self.load(path: path, vault: vault, author: author)
        }
        state = result
        refreshAvailableDates()
    }

    /// Cheap polling reload — only reparse when the byte size changed.
    func reloadIfChanged() async {
        guard case .loaded(let doc) = state else {
            await reload()
            return
        }
        let path = selectedRelativePath
        let vault = self.vault
        let currentBytes = doc.sourceBytes
        let changed = await vault.performIO {
            guard let data = vault.readFileIfExists(relativePath: path) else { return true }
            return data.count != currentBytes
        }
        if changed { await reload() }
    }

    nonisolated private static func load(path: String, vault: VaultAccess, author: String) -> State {
        do {
            let data = try vault.readFile(relativePath: path)
            guard let text = String(data: data, encoding: .utf8) else {
                return .failed("File is not valid UTF-8.")
            }
            let doc = try ActionItemsParser.parse(
                text: text,
                sourceURL: URL(fileURLWithPath: path),
                sourceBytes: data.count,
                authorName: author
            )
            return .loaded(doc)
        } catch VaultAccess.VaultError.fileNotFound {
            return .missing
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private func refreshAvailableDates() {
        let vault = self.vault
        Task { [weak self] in
            let names = await vault.performIO {
                (try? vault.listDirectory(relativePath: "action-items")) ?? []
            }
            let dates = names.compactMap { name -> Date? in
                guard name.hasPrefix("action-items-"), name.hasSuffix(".md") else { return nil }
                let stem = String(name.dropFirst("action-items-".count).dropLast(3))
                return ActionItemsParser.dayFormatter.date(from: stem)
            }.sorted()
            self?.availableDates = dates
        }
    }

    // MARK: - Mutations

    func setDone(_ task: ActionTask, done: Bool) async throws {
        let path = selectedRelativePath
        let vault = self.vault
        try await vault.performIO {
            try ActionItemsWriter.markDone(task, done: done, in: path, vault: vault)
        }
        await reload()
    }

    func snooze(_ task: ActionTask, until: Date, fromKind: ActionSection.Kind?) async throws {
        let path = selectedRelativePath
        let vault = self.vault
        try await vault.performIO {
            try ActionItemsWriter.snooze(task, until: until, fromKind: fromKind, in: path, vault: vault)
        }
        await reload()
    }

    func addComment(_ task: ActionTask, text: String) async throws {
        let path = selectedRelativePath
        let vault = self.vault
        let author = settings.authorName
        try await vault.performIO {
            try ActionItemsWriter.addComment(task, author: author, text: text, in: path, vault: vault)
        }
        await reload()
    }
}
