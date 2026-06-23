import SwiftUI

/// Small color-coded capsule for a per-file item's lifecycle status.
struct ItemStatusPill: View {
    let status: ItemStatus

    var body: some View {
        Text(status.displayName.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.15)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
            .fixedSize()
    }

    private var tint: Color {
        switch status {
        case .open:        return .blue
        case .inProgress:  return .orange
        case .done:        return .green
        case .dropped:     return .red
        case .unknown:     return .secondary
        }
    }
}
