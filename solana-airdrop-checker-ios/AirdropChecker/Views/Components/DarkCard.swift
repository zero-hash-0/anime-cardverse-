import SwiftUI

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
                    .fill(ThemeTokens.Card.top)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [ThemeTokens.Card.innerHighlight, Color.clear],
                                    startPoint: .top,
                                    endPoint: .init(x: 0.5, y: 0.30)
                                )
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(ThemeTokens.Card.border, lineWidth: 1)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: ThemeTokens.Card.shadow, radius: ThemeTokens.Shadow.softRadius, x: 0, y: ThemeTokens.Shadow.softY)
            .shadow(color: ThemeTokens.Card.shadowSecondary, radius: 8, x: 0, y: 3)
    }
}
