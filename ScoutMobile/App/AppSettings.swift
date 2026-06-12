import Foundation
import Combine

/// User preferences, mirroring the desktop app's Settings keys.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    @Published var linearWorkspace: String {
        didSet { defaults.set(linearWorkspace, forKey: "linearWorkspace") }
    }
    @Published var authorName: String {
        didSet { defaults.set(authorName, forKey: "authorName") }
    }
    /// Master toggle: local notification when a scout run finishes.
    @Published var notifyOnRunFinished: Bool {
        didSet { defaults.set(notifyOnRunFinished, forKey: "notifyOnRunFinished") }
    }
    /// When true, only failed / rate-limited runs notify.
    @Published var notifyFailuresOnly: Bool {
        didSet { defaults.set(notifyFailuresOnly, forKey: "notifyFailuresOnly") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.linearWorkspace = defaults.string(forKey: "linearWorkspace") ?? ""
        self.authorName = defaults.string(forKey: "authorName") ?? "user"
        self.notifyOnRunFinished = defaults.object(forKey: "notifyOnRunFinished") as? Bool ?? true
        self.notifyFailuresOnly = defaults.object(forKey: "notifyFailuresOnly") as? Bool ?? false
    }
}
