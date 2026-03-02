import SwiftUI

struct DesignSystem {
    enum Colors {
        static let textPrimary = ThemeTokens.Text.primary
        static let textSecondary = ThemeTokens.Text.secondary
        static let textMuted = ThemeTokens.Text.muted
        static let accent = ThemeTokens.Accent.intelligenceBlue
        static let safe = ThemeTokens.Accent.green
        static let warning = ThemeTokens.Accent.elevated
        static let danger = ThemeTokens.Accent.critical
        static let surface = ThemeTokens.Card.top
        static let surfaceElevated = ThemeTokens.Card.innerSurface
        static let border = ThemeTokens.Card.border
    }

    enum Typography {
        static let h2 = Font.system(size: 28, weight: .semibold)
        static let cardTitle = Font.system(size: 20, weight: .semibold)
        static let body = Font.system(size: 16, weight: .regular)
        static let meta = Font.system(size: 13, weight: .medium)
        static let metricMedium = Font.system(size: 34, weight: .bold)
        static let metricLarge = Font.system(size: 56, weight: .bold)
    }

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }

    enum Radius {
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
    }
}

private struct CardStyleLeftModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [ThemeTokens.Card.top, ThemeTokens.Card.bottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(ThemeTokens.Card.border, lineWidth: 1)
                    )
            )
            .shadow(color: ThemeTokens.Card.shadow, radius: ThemeTokens.Shadow.softRadius, x: 0, y: ThemeTokens.Shadow.softY)
    }
}

private struct IntelligenceCardStyleModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [ThemeTokens.Card.top, ThemeTokens.Card.innerSurface],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(ThemeTokens.Card.border, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func cardStyleLeft(cornerRadius: CGFloat) -> some View {
        modifier(CardStyleLeftModifier(cornerRadius: cornerRadius))
    }

    func intelligenceCardStyle(cornerRadius: CGFloat) -> some View {
        modifier(IntelligenceCardStyleModifier(cornerRadius: cornerRadius))
    }
}

struct IntelligenceCard<Content: View>: View {
    enum Severity {
        case normal
        case caution
        case danger
    }

    var severity: Severity = .normal
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                    .fill(ThemeTokens.Card.innerSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
    }

    private var borderColor: Color {
        switch severity {
        case .normal: return ThemeTokens.Card.border
        case .caution: return ThemeTokens.Accent.elevated.opacity(0.45)
        case .danger: return ThemeTokens.Accent.critical.opacity(0.45)
        }
    }
}
