import SwiftUI

/// Kraken-style anchored surface card.
/// Uses flat dark fill, crisp border, and tight low-opacity shadow.
struct DarkCard<Content: View>: View {
    var cornerRadius: CGFloat = ThemeTokens.Layout.cardRadius
    var contentPadding: CGFloat = 18
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ThemeTokens.Card.surface)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(ThemeTokens.Card.highlightTop)
                            .frame(height: 2)
                            .clipShape(
                                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(ThemeTokens.Card.stroke, lineWidth: 1.0)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(
                color: ThemeTokens.Card.shadow,
                radius: ThemeTokens.Card.shadowRadius,
                x: 0,
                y: ThemeTokens.Card.shadowY
            )
    }
}
