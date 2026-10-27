import SwiftUI
import UniformTypeIdentifiers

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPicker = false
    @State private var errorMessage: String?

    var body: some View {
        layout
            .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url):
                    adopt(url)
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
    }

    /// iPhone Duo: on a partially folded inner display the intro and the button
    /// go on opposite sides of the fold instead of straddling it — side by side
    /// with the button trailing in the book pose, intro above and button on the
    /// stable bottom half in the laptop pose. Otherwise (and when built with an
    /// SDK older than iOS 27.1) it's the single centered column.
    @ViewBuilder
    private var layout: some View {
        #if compiler(>=6.4) // Xcode 27+; ReservedRegion needs the iOS 27.1 SDK
        if #available(iOS 27.1, *) {
            GeometryReader { proxy in
                Group {
                    if let fold = proxy.reservedRegions(kind: .division).first?.frame {
                        foldedLayout(around: fold, in: proxy.size)
                    } else {
                        singleColumn
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            singleColumn
        }
        #else
        singleColumn
        #endif
    }

    private var singleColumn: some View {
        VStack(spacing: 24) {
            Spacer()
            intro
            Spacer()
            actions
        }
    }

    /// Splits around an active fold, sizing each side to its region so nothing
    /// interactive lands in the crease (per Apple's `ReservedRegion` example).
    @ViewBuilder
    private func foldedLayout(around fold: CGRect, in size: CGSize) -> some View {
        if fold.height > fold.width {
            // Book pose: the fold runs vertically.
            HStack(spacing: 0) {
                intro.frame(width: max(fold.minX, 0))
                Color.clear.frame(width: fold.width)
                actions.frame(width: max(size.width - fold.maxX, 0))
            }
        } else {
            // Laptop pose: the fold runs horizontally.
            VStack(spacing: 0) {
                intro.frame(height: max(fold.minY, 0))
                Color.clear.frame(height: fold.height)
                actions.frame(height: max(size.height - fold.maxY, 0))
            }
        }
    }

    private var intro: some View {
        VStack(spacing: 24) {
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
        }
    }

    private var actions: some View {
        VStack(spacing: 24) {
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
