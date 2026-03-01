import SwiftUI

struct TrendChip: View {
    let value: Double
    let suffix: String

    private var isNeutral: Bool { abs(value) < 0.05 }
    private var isRiskIncrease: Bool { value > 0.05 }

    private var iconName: String {
        if isNeutral { return "minus" }
        return isRiskIncrease ? "arrow.up.right" : "arrow.down.right"
    }

    private var chipColor: Color {
        if isNeutral { return DesignSystem.Colors.textSecondary }
        // Up-risk = critical, down-risk = safe
        return isRiskIncrease ? DesignSystem.Colors.danger : DesignSystem.Colors.safe
    }

    private var label: String {
        if isNeutral { return "0.0% (\(suffix))" }
        return String(format: "%@%.1f%% (%@)", isRiskIncrease ? "+" : "", value, suffix)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 10, weight: .bold))
            Text(label)
                .font(DesignSystem.Typography.meta.weight(.semibold))
        }
        .foregroundStyle(chipColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(chipColor.opacity(0.12), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(chipColor.opacity(0.25), lineWidth: 0.8)
        )
    }
}
