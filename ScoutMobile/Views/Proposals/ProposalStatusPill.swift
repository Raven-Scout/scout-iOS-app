import SwiftUI

/// Small color-coded capsule for a proposal's lifecycle status.
struct ProposalStatusPill: View {
    let status: ProposalStatus

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
        case .proposed:  return .blue
        case .pending:   return .teal
        case .approved:  return .green
        case .rejected:  return .red
        case .applied:   return .purple
        case .unknown:   return .secondary
        }
    }
}
