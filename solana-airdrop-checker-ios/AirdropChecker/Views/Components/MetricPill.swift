import SwiftUI

enum ThreatLevel: String {
    case low = "Low"
    case guarded = "Guarded"
    case elevated = "Elevated"
    case critical = "Critical"

    var color: Color {
        switch self {
        case .low: return DesignSystem.Colors.safe
        case .guarded: return DesignSystem.Colors.accent
        case .elevated: return DesignSystem.Colors.warning
        case .critical: return DesignSystem.Colors.danger
        }
    }
}

struct MetricPill: View {
    let level: ThreatLevel

    var body: some View {
        Text(level.rawValue)
            .font(DesignSystem.Typography.meta.weight(.semibold))
            .foregroundStyle(level.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(level.color.opacity(0.14), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(level.color.opacity(0.28), lineWidth: 0.9)
            )
    }
}
