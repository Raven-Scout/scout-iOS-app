import SwiftUI

/// One per-file Wishlist/Research item as a card: header (date + title +
/// priority/status pills), optional source/area line, markdown body, and —
/// for active items — Done / Drop actions. Owns its in-flight + error state so
/// a slow or failed write surfaces on the card itself.
struct PerFileItemCardView: View {
    let item: PerFileItem
    /// Display label for the optional source/area field (e.g. "Source", "Area").
    let optionalLabel: String?
    /// Performs the write. Throws so the card can show an inline error.
    /// `nil` for resolved (read-only) items.
    var onResolve: (@MainActor (ItemResolution) async throws -> Void)?

    @State private var inFlight: ItemResolution?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let label = optionalLabel, let value = optionalValue, !value.isEmpty {
                Text("\(label): \(value)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !item.bodyBlocks.isEmpty {
                MarkdownBodyView(blocks: item.bodyBlocks)
            }
            if item.isActive, onResolve != nil {
                actions
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var optionalValue: String? { item.source ?? item.area }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if !item.date.isEmpty {
                    Text(item.date)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            ItemPriorityPill(priority: item.priority)
            ItemStatusPill(status: item.status)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            actButton("Done", systemImage: "checkmark", resolution: .done, tint: .green)
            actButton("Drop", systemImage: "xmark", resolution: .dropped, tint: .secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func actButton(
        _ label: String,
        systemImage: String,
        resolution: ItemResolution,
        tint: Color
    ) -> some View {
        let isBusy = inFlight == resolution
        Button {
            resolve(resolution)
        } label: {
            HStack(spacing: 5) {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
                Text(label)
            }
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .tint(tint)
        .disabled(inFlight != nil)
    }

    private func resolve(_ resolution: ItemResolution) {
        guard let onResolve else { return }
        inFlight = resolution
        errorText = nil
        Task {
            do {
                try await onResolve(resolution)
            } catch {
                errorText = "Couldn't update the file — \(error.localizedDescription)"
            }
            inFlight = nil
        }
    }
}
