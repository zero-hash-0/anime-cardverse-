import SwiftUI

struct ProtectionControlsCard: View {
    @ObservedObject var viewModel: DashboardViewModel

    private var level: ProtectionLevel { viewModel.protectionLevel }
    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private var lastScanText: String {
        guard let checkedAt = viewModel.lastCheckedAt else { return "Last scan: -" }
        return "Last scan: \(relativeFormatter.localizedString(for: checkedAt, relativeTo: Date()))"
    }

    var body: some View {
        DarkCard(contentPadding: 16) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: 8) {
                    Text("Protection Controls")
                        .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                        .foregroundStyle(ThemeTokens.Text.primary)
                    Spacer()
                    Circle()
                        .fill(level.severityColor)
                        .frame(width: 7, height: 7)
                    Text(level.title)
                        .font(DesignSystem.Typography.meta.weight(.semibold))
                        .foregroundStyle(ThemeTokens.Text.primary.opacity(0.92))
                }

                Picker(
                    "Protection Level",
                    selection: Binding(
                        get: { viewModel.protectionLevel },
                        set: { viewModel.setProtectionLevel($0) }
                    )
                ) {
                    ForEach(ProtectionLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .tint(ThemeTokens.Accent.actionBlue)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: ThemeTokens.Layout.cardInnerRadius, style: .continuous)
                        .fill(ThemeTokens.Card.surfaceAlt)
                        .overlay(
                            RoundedRectangle(cornerRadius: ThemeTokens.Layout.cardInnerRadius, style: .continuous)
                                .stroke(ThemeTokens.Card.divider, lineWidth: 1)
                        )
                )

                Text(level.detail)
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(ThemeTokens.Text.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text("Status: \(level.title)")
                        .font(DesignSystem.Typography.meta.weight(.semibold))
                        .foregroundStyle(ThemeTokens.Text.primary.opacity(0.92))
                    Spacer()
                    Text(lastScanText)
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(ThemeTokens.Text.secondary.opacity(0.9))
                        .monospacedDigit()
                }

                NavigationLink {
                    ProtectionSettingsView(viewModel: viewModel)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ThemeTokens.Accent.intelligenceBlue)
                        Text("Protection Settings")
                            .font(DesignSystem.Typography.meta.weight(.semibold))
                            .foregroundStyle(ThemeTokens.Text.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(ThemeTokens.Text.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(ThemeTokens.Card.innerSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(ThemeTokens.Card.border, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
