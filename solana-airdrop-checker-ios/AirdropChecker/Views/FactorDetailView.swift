import SwiftUI

struct FactorDetailView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let factor: ExposureFactor
    let snapshot: ExposureSnapshot

    @State private var actionFeedback: String?

    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var confidenceLabel: String {
        let value = abs(factor.delta24h)
        if value < 0.3 { return "Low" }
        if value <= 1.0 { return "Medium" }
        return "High"
    }

    private var deltaColor: Color {
        let delta = factor.delta24h
        if abs(delta) < 0.05 { return ThemeTokens.Text.secondary }
        if delta < 0 { return ThemeTokens.Accent.green }

        switch snapshot.tier {
        case .guarded, .stable:
            return ThemeTokens.Accent.elevated
        case .elevated, .critical:
            return ThemeTokens.Accent.critical
        }
    }

    private var evidence: [EvidenceItem] {
        viewModel.evidenceItems(for: factor.id)
    }

    private var recommendedActions: [String] {
        switch factor.id {
        case "contract_risk":
            return [
                "Review recent contract approvals",
                "Revoke suspicious allowances",
                "Enable high-risk interaction prompt"
            ]
        case "liquidity_exposure":
            return [
                "Reduce concentrated pool exposure",
                "Set alert for pool composition changes",
                "Limit high-volatility LP positions"
            ]
        case "behavioral_signals":
            return [
                "Enable real-time anomaly alerts",
                "Lock high-risk interactions",
                "Require confirmation for novel contracts"
            ]
        default:
            return [
                "Add protocol to watchlist",
                "Enable high-risk-only alerts",
                "Review counterparty trust changes"
            ]
        }
    }

    private var scoringNotes: [String] {
        switch factor.id {
        case "contract_risk":
            return [
                "Weights execution risk concentration and contract trust signals.",
                "Penalizes repeated interactions with unverified programs.",
                "Rewards stable interaction history with known protocols."
            ]
        case "liquidity_exposure":
            return [
                "Measures concentration across pools and venues.",
                "Penalizes exposure clustering in volatile pairs.",
                "Accounts for recent rebalance velocity."
            ]
        case "behavioral_signals":
            return [
                "Compares interaction cadence vs baseline profile.",
                "Flags novelty spikes in contract usage.",
                "Scores acceleration in risk-sensitive actions."
            ]
        default:
            return [
                "Uses protocol trust and counterparty concentration.",
                "Penalizes lower-rated venues with rising usage.",
                "Blends recent and historical trust movement."
            ]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                headerCard
                evidenceCard
                actionsCard
                notesCard
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.md)
            .padding(.bottom, DesignSystem.Spacing.xl)
        }
        .background(ThemeTokens.Background.base.ignoresSafeArea())
        .navigationTitle("Factor Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        DarkCard(contentPadding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text(factor.name)
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)

                Text("\(factor.value)")
                    .font(DesignSystem.Typography.metricLarge)
                    .foregroundStyle(ThemeTokens.Text.primary)
                    .monospacedDigit()

                HStack(spacing: 8) {
                    Text(deltaText(factor.delta24h))
                        .font(DesignSystem.Typography.body.weight(.semibold))
                        .foregroundStyle(deltaColor)
                        .monospacedDigit()
                    Text("Confidence: \(confidenceLabel)")
                        .font(DesignSystem.Typography.meta.weight(.semibold))
                        .foregroundStyle(ThemeTokens.Text.secondary)
                }

                Text(meaningText(for: factor.id))
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(ThemeTokens.Text.secondary)
            }
        }
    }

    private var evidenceCard: some View {
        DarkCard(contentPadding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Evidence")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)

                ForEach(evidence) { item in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(DesignSystem.Typography.body.weight(.semibold))
                                .foregroundStyle(ThemeTokens.Text.primary)
                            Text(item.subtitle)
                                .font(DesignSystem.Typography.meta)
                                .foregroundStyle(ThemeTokens.Text.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(severityLabel(item.severity))
                                .font(DesignSystem.Typography.meta.weight(.semibold))
                                .foregroundStyle(item.severity.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(item.severity.color.opacity(0.14), in: Capsule(style: .continuous))
                            Text(relativeFormatter.localizedString(for: item.timestamp, relativeTo: Date()))
                                .font(DesignSystem.Typography.meta)
                                .foregroundStyle(ThemeTokens.Text.secondary)
                                .monospacedDigit()
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ThemeTokens.Text.secondary.opacity(0.75))
                    }
                    .padding(.vertical, 3)

                    if item.id != evidence.last?.id {
                        Rectangle()
                            .fill(ThemeTokens.Card.divider)
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    private var actionsCard: some View {
        DarkCard(contentPadding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recommended Actions")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)

                ForEach(recommendedActions, id: \.self) { action in
                    Button {
                        actionFeedback = "Action queued: \(action)"
                    } label: {
                        HStack {
                            Text(action)
                                .font(DesignSystem.Typography.body.weight(.semibold))
                                .foregroundStyle(ThemeTokens.Text.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ThemeTokens.Accent.intelligenceBlue)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(ThemeTokens.Card.innerSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(ThemeTokens.Card.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let actionFeedback {
                    Text(actionFeedback)
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(ThemeTokens.Text.secondary)
                }
            }
        }
    }

    private var notesCard: some View {
        DarkCard(contentPadding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("How we score this")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)

                Text(factor.weightPercentText)
                    .font(DesignSystem.Typography.body.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)

                ForEach(scoringNotes, id: \.self) { note in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(DesignSystem.Typography.body.weight(.semibold))
                            .foregroundStyle(ThemeTokens.Text.secondary)
                        Text(note)
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(ThemeTokens.Text.secondary)
                    }
                }
            }
        }
    }

    private func severityLabel(_ severity: EvidenceSeverity) -> String {
        switch severity {
        case .low:
            return "Low"
        case .elevated:
            return "Elevated"
        case .critical:
            return "Critical"
        }
    }

    private func deltaText(_ delta: Double) -> String {
        if delta == 0 { return "0.0%" }
        return String(format: "%@%.1f%%", delta > 0 ? "+" : "", delta)
    }

    private func meaningText(for factorID: String) -> String {
        switch factorID {
        case "contract_risk":
            return "What this means: Contract trust and permission exposure are trending in a risk-sensitive direction."
        case "liquidity_exposure":
            return "What this means: Capital concentration in volatile pools is raising exposure pressure."
        case "behavioral_signals":
            return "What this means: Interaction behavior has deviated from your normal baseline profile."
        default:
            return "What this means: Counterparty trust distribution is becoming less balanced."
        }
    }
}
