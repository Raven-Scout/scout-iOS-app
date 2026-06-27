import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings

    @State private var showPicker = false
    @State private var pickError: String?
    @State private var notificationsAuthorized: Bool?
    @FocusState private var focusedField: Field?

    private enum Field {
        case linearWorkspace
        case authorName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Scout folder") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.vault.displayPath.isEmpty ? "Not selected" : model.vault.displayPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    Button("Change folder…") { showPicker = true }
                    if let pickError {
                        Text(pickError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    TextField("Workspace slug (e.g. acme-co)", text: $settings.linearWorkspace)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .linearWorkspace)
                        .submitLabel(.done)
                } header: {
                    Text("Linear")
                } footer: {
                    Text("Used to open Linear issues like PROJ-3026 in the Linear app.")
                }

                Section {
                    TextField("Your name", text: $settings.authorName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .authorName)
                        .submitLabel(.done)
                } header: {
                    Text("Authorship")
                } footer: {
                    Text("Shown next to comments you add to action items.")
                }

                Section {
                    Toggle("Notify when a run finishes", isOn: $settings.notifyOnRunFinished)
                    Toggle("Failures only", isOn: $settings.notifyFailuresOnly)
                        .disabled(!settings.notifyOnRunFinished)
                    if notificationsAuthorized == false {
                        Label {
                            Text("Notifications are disabled in iOS Settings.")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Scout checks for new runs in the background. iOS controls how often background checks happen — opening the app regularly keeps them frequent.")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Vault format", value: "scout-plugin")
                    Link("Scout desktop app", destination: URL(string: "https://github.com/jordanrburger/Scout")!)
                }
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    do {
                        try model.adoptVault(url: url)
                        pickError = model.vault.looksLikeScoutVault()
                            ? nil
                            : "That folder doesn't look like a Scout vault (no action-items/)."
                    } catch {
                        pickError = error.localizedDescription
                    }
                case .failure(let error):
                    pickError = error.localizedDescription
                }
            }
            .task {
                let status = await UNUserNotificationCenter.current().notificationSettings()
                notificationsAuthorized = status.authorizationStatus == .authorized
                    || status.authorizationStatus == .provisional
                if status.authorizationStatus == .notDetermined {
                    notificationsAuthorized = await NotificationService.requestAuthorization()
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
