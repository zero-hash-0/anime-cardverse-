import SwiftUI
import UIKit

struct ProtectionSettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @State private var bannerMessage: String?

    private var alertsEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.protectionSettings.alertsEnabled },
            set: { value in
                viewModel.updateProtectionSettings { settings in
                    settings.alertsEnabled = value
                }
            }
        )
    }

    private var highRiskOnlyBinding: Binding<Bool> {
        Binding(
            get: { viewModel.protectionSettings.highRiskOnly },
            set: { value in
                viewModel.updateProtectionSettings { settings in
                    settings.highRiskOnly = value
                }
            }
        )
    }

    private var deliveryBinding: Binding<AlertDelivery> {
        Binding(
            get: { viewModel.protectionSettings.delivery },
            set: { value in
                viewModel.updateProtectionSettings { settings in
                    settings.delivery = value
                }
            }
        )
    }

    private var sensitivityBinding: Binding<Sensitivity> {
        Binding(
            get: { viewModel.protectionSettings.anomalySensitivity },
            set: { value in
                viewModel.updateProtectionSettings { settings in
                    settings.anomalySensitivity = value
                }
            }
        )
    }

    private var exposureDeltaBinding: Binding<Int> {
        Binding(
            get: { viewModel.protectionSettings.exposureDeltaNotifyPercent },
            set: { value in
                viewModel.updateProtectionSettings { settings in
                    settings.exposureDeltaNotifyPercent = min(20, max(1, value))
                }
            }
        )
    }

    private var criticalThresholdBinding: Binding<Int> {
        Binding(
            get: { viewModel.protectionSettings.criticalThreshold },
            set: { value in
                viewModel.updateProtectionSettings { settings in
                    settings.criticalThreshold = min(95, max(50, value))
                }
            }
        )
    }

    private var scanIntervalBinding: Binding<Int> {
        Binding(
            get: { viewModel.protectionSettings.autoScanIntervalMinutes },
            set: { value in
                viewModel.updateProtectionSettings { settings in
                    settings.autoScanIntervalMinutes = value
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                headerCard
                alertPolicyCard
                sensitivityCard
                thresholdsCard
                scanCadenceCard
                operationalCard
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.md)
        }
        .navigationTitle("Protection Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(ThemeTokens.Background.base, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if let bannerMessage {
                Text(bannerMessage)
                    .font(DesignSystem.Typography.meta.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)
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
                    .padding(.bottom, DesignSystem.Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: bannerMessage)
    }

    private var headerCard: some View {
        DarkCard(contentPadding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Protection Settings")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)
                Text("Policy configuration for monitoring and alerts.")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(ThemeTokens.Text.secondary)
            }
        }
    }

    private var alertPolicyCard: some View {
        DarkCard(contentPadding: 16) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Alert Policy")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)

                policyToggleRow(title: "Enable Alerts", isOn: alertsEnabledBinding)
                policyToggleRow(title: "High-risk only", isOn: highRiskOnlyBinding)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Delivery")
                        .font(DesignSystem.Typography.meta.weight(.semibold))
                        .foregroundStyle(ThemeTokens.Text.secondary)

                    Picker("Delivery", selection: deliveryBinding) {
                        ForEach(AlertDelivery.allCases) { delivery in
                            Text(delivery.title).tag(delivery)
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
                }

                Text("Delivery channel routing for policy events. Push and In-app are currently policy stubs.")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(ThemeTokens.Text.secondary)
            }
        }
    }

    private var sensitivityCard: some View {
        DarkCard(contentPadding: 16) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Sensitivity")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)

                Picker("Anomaly Sensitivity", selection: sensitivityBinding) {
                    ForEach(Sensitivity.allCases) { sensitivity in
                        Text(sensitivity.title).tag(sensitivity)
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

                Text("Controls how aggressively PrismMesh flags deviations.")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(ThemeTokens.Text.secondary)
            }
        }
    }

    private var thresholdsCard: some View {
        DarkCard(contentPadding: 16) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Thresholds")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Notify when Exposure increases by")
                            .font(DesignSystem.Typography.meta.weight(.semibold))
                            .foregroundStyle(ThemeTokens.Text.secondary)
                        Spacer()
                        Text("\(viewModel.protectionSettings.exposureDeltaNotifyPercent)%")
                            .font(DesignSystem.Typography.meta.weight(.semibold))
                            .foregroundStyle(ThemeTokens.Text.primary)
                            .monospacedDigit()
                    }
                    Stepper(value: exposureDeltaBinding, in: 1...20) {
                        EmptyView()
                    }
                    .labelsHidden()
                }
                .padding(12)
                .background(ThemeTokens.Card.innerSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Critical tier threshold")
                            .font(DesignSystem.Typography.meta.weight(.semibold))
                            .foregroundStyle(ThemeTokens.Text.secondary)
                        Spacer()
                        Text("\(viewModel.protectionSettings.criticalThreshold)")
                            .font(DesignSystem.Typography.meta.weight(.semibold))
                            .foregroundStyle(ThemeTokens.Text.primary)
                            .monospacedDigit()
                    }
                    Stepper(value: criticalThresholdBinding, in: 50...95) {
                        EmptyView()
                    }
                    .labelsHidden()
                }
                .padding(12)
                .background(ThemeTokens.Card.innerSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Threshold policies define when risk events are escalated into operator alerts.")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(ThemeTokens.Text.secondary)
            }
        }
    }

    private var scanCadenceCard: some View {
        DarkCard(contentPadding: 16) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Scan Cadence")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)

                Picker("Auto-scan interval", selection: scanIntervalBinding) {
                    Text("10m").tag(10)
                    Text("30m").tag(30)
                    Text("60m").tag(60)
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

                Text("Sets the baseline interval for auto-scan scheduling; retry backoff may extend it on repeated failures.")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(ThemeTokens.Text.secondary)
            }
        }
    }

    private var operationalCard: some View {
        DarkCard(contentPadding: 16) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Operational")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)

                Button {
                    viewModel.runTestAlertPolicyEvent()
                    showBanner("Test alert queued (stub)")
                } label: {
                    settingsActionRow(title: "Run test alert", icon: "bell.badge")
                }
                .buttonStyle(.plain)

                Button {
                    UIPasteboard.general.string = exportDiagnosticsBlock
                    showBanner("Diagnostics copied to clipboard")
                } label: {
                    settingsActionRow(title: "Export diagnostics", icon: "doc.on.doc")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func policyToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(DesignSystem.Typography.meta.weight(.semibold))
                .foregroundStyle(ThemeTokens.Text.secondary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(ThemeTokens.Accent.intelligenceBlue)
        }
        .padding(12)
        .background(ThemeTokens.Card.innerSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func settingsActionRow(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ThemeTokens.Accent.intelligenceBlue)
            Text(title)
                .font(DesignSystem.Typography.meta.weight(.semibold))
                .foregroundStyle(ThemeTokens.Text.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ThemeTokens.Text.secondary)
        }
        .padding(12)
        .background(ThemeTokens.Card.innerSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ThemeTokens.Card.border, lineWidth: 1)
        )
    }

    private var exportDiagnosticsBlock: String {
        let settings = viewModel.protectionSettings
        return """
        PrismMesh Protection Diagnostics
        Level: \(viewModel.protectionLevel.title)
        Alerts enabled: \(settings.alertsEnabled)
        High-risk only: \(settings.highRiskOnly)
        Delivery: \(settings.delivery.rawValue)
        Sensitivity: \(settings.anomalySensitivity.rawValue)
        Exposure delta threshold: \(settings.exposureDeltaNotifyPercent)%
        Critical threshold: \(settings.criticalThreshold)
        Auto-scan interval: \(settings.autoScanIntervalMinutes)m
        """
    }

    private func showBanner(_ text: String) {
        bannerMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    bannerMessage = nil
                }
            }
        }
    }
}
