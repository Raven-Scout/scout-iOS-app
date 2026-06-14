import SwiftUI

/// Renders a proposal body as a vertical stack of prose paragraphs (inline
/// markdown) and verbatim code panels. Keeps the dense bold-label-and-code
/// proposal text readable instead of collapsing it into one wall.
struct ProposalBodyView: View {
    let blocks: [ProposalBodyBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block {
                case .prose(let text):
                    Text(InlineMarkdown.attributed(text))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(_, let code):
                    codePanel(code)
                }
            }
        }
    }

    private func codePanel(_ code: String) -> some View {
        Text(code)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemBackground))
            )
            .fixedSize(horizontal: false, vertical: true)
    }
}
