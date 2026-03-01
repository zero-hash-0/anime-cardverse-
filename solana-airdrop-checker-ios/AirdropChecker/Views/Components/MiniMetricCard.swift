import SwiftUI

struct MiniMetricCard: View {
    let title: String
    let value: String
    let trendText: String
    let severityColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(severityColor)
                    .frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)

            Text(trendText)
                .font(DesignSystem.Typography.meta.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ThemeTokens.Card.innerSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(ThemeTokens.Card.border, lineWidth: 1)
                )
        )
    }
}
