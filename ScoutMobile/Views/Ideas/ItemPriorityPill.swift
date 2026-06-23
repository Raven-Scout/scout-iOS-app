import SwiftUI

/// Small color-coded capsule for a per-file item's priority.
struct ItemPriorityPill: View {
    let priority: ItemPriority

    var body: some View {
        Text(priority.displayName.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.15)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
            .fixedSize()
    }

    private var tint: Color {
        switch priority {
        case .urgent: return .red
        case .high:   return .orange
        case .medium: return .blue
        case .low:    return .secondary
        }
    }
}
