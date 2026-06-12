import SwiftUI

/// Lightweight design tokens echoing the desktop app's palette, adapted to
/// iOS system styling (dynamic type, dark mode come free from the system).
enum DS {
    static func color(for kind: ActionSection.Kind) -> Color {
        switch kind {
        case .urgent:   return .red
        case .todo:     return .yellow
        case .watching: return .green
        case .focus:    return .orange
        case .meetings: return .blue
        case .done:     return .gray
        case .digest:   return .indigo
        case .personal: return .teal
        case .neutral:  return .secondary
        }
    }

    static func color(for status: RunStatus) -> Color {
        switch status {
        case .success:            return .green
        case .failure:            return .red
        case .timeout:            return .orange
        case .running:            return .blue
        case .rateLimited:        return .orange
        case .orphaned:           return .gray
        case .skippedBudget:      return .gray
        case .skippedConcurrency: return .gray
        case .scheduled:          return .secondary
        }
    }

    static func color(for slotType: SlotType) -> Color {
        switch slotType {
        case .briefing:      return .blue
        case .consolidation: return .teal
        case .dreaming:      return .purple
        case .research:      return .orange
        case .manual:        return .gray
        }
    }

    static func icon(for status: RunStatus) -> String {
        switch status {
        case .success:            return "checkmark.circle.fill"
        case .failure:            return "xmark.circle.fill"
        case .timeout:            return "clock.badge.exclamationmark"
        case .running:            return "circle.dotted.circle"
        case .rateLimited:        return "speedometer"
        case .orphaned:           return "questionmark.circle"
        case .skippedBudget:      return "dollarsign.circle"
        case .skippedConcurrency: return "person.2.slash"
        case .scheduled:          return "calendar"
        }
    }

    static func icon(for slotType: SlotType) -> String {
        switch slotType {
        case .briefing:      return "sunrise"
        case .consolidation: return "arrow.triangle.merge"
        case .dreaming:      return "moon.zzz"
        case .research:      return "magnifyingglass"
        case .manual:        return "hand.tap"
        }
    }
}

/// Renders a markdown-ish inline string (bold, strikethrough, code,
/// wikilinks) as styled Text. Wikilinks are converted into custom-scheme
/// links so views can intercept taps via `.environment(\.openURL, …)`.
enum InlineMarkdown {
    static func attributed(_ raw: String, wikilinksTappable: Bool = false) -> AttributedString {
        var s = raw
        // Convert wikilinks to standard markdown links (or plain text).
        if wikilinksTappable {
            s = replace(s, #"\[\[([^\]|]+?)\|([^\]]+?)\]\]"#, "[$2](scoutwiki://$1)")
            s = replace(s, #"\[\[([^\]|]+?)\]\]"#, "[$1](scoutwiki://$1)")
        } else {
            s = replace(s, #"\[\[([^\]|]+?)\|([^\]]+?)\]\]"#, "$2")
            s = replace(s, #"\[\[([^\]|]+?)\]\]"#, "$1")
        }
        if let attributed = try? AttributedString(
            markdown: s,
            options: .init(allowsExtendedAttributes: false, interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(raw)
    }

    private static func replace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}

extension Date {
    var shortTime: String {
        formatted(date: .omitted, time: .shortened)
    }
    var dayLabel: String {
        if Calendar.current.isDateInToday(self) { return "Today" }
        if Calendar.current.isDateInYesterday(self) { return "Yesterday" }
        if Calendar.current.isDateInTomorrow(self) { return "Tomorrow" }
        return formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

extension TimeInterval {
    var compactDuration: String {
        let total = Int(self)
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m \(total % 60)s" }
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }
}
