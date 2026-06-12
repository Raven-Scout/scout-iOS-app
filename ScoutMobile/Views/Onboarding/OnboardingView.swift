import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPicker = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "binoculars.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Scout")
                .font(.largeTitle.bold())

            Text("Your daily briefings, action items, and session history — read straight from your Scout vault in iCloud.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                Label("Open your Obsidian folder in iCloud Drive", systemImage: "1.circle")
                Label("Select the Scout vault folder", systemImage: "2.circle")
                Label("Get notified when new runs finish", systemImage: "3.circle")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                showPicker = true
            } label: {
                Text("Choose Scout Folder")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                adopt(url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func adopt(_ url: URL) {
        do {
            try model.adoptVault(url: url)
            if !model.vault.looksLikeScoutVault() {
                errorMessage = "Heads up: that folder doesn't contain an action-items directory yet — pick your Scout vault folder if this was the wrong one. You can change it in Settings."
            } else {
                errorMessage = nil
            }
        } catch {
            errorMessage = "Could not save access to that folder: \(error.localizedDescription)"
        }
    }
}
