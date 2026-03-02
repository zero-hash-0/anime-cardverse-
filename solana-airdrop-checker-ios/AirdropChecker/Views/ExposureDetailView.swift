import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct ExposureDetailView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let currentExposureIndex: Int

    @State private var selectedRange: RiskHistoryRange = .sevenDays
    @State private var expandedFactorIDs: Set<String> = []

    private var snapshots: [ExposureSnapshot] {
        viewModel.exposureSnapshots(range: selectedRange, currentIndex: canonicalExposureIndex)
    }

    private var canonicalExposureIndex: Int {
        viewModel.exposureIndex > 0 ? viewModel.exposureIndex : currentExposureIndex
    }

    private var canonicalFactors: [ExposureFactor] {
        if !viewModel.exposureFactorsLive.isEmpty {
            return viewModel.exposureFactorsLive
        }
        return viewModel.computeExposureSnapshot().factors
    }

    private var latestSnapshot: ExposureSnapshot {
        snapshots.last ?? ExposureSnapshot(
            date: Date(),
            exposureIndex: canonicalExposureIndex,
            tier: viewModel.exposureTier(for: canonicalExposureIndex),
            factors: canonicalFactors
        )
    }

    private var trendWindowDays: Int {
        switch selectedRange {
        case .sevenDays: return 1
        case .thirtyDays: return 7
        case .ninetyDays: return 30
        }
    }

    private var trendSuffix: String {
        switch selectedRange {
        case .sevenDays: return "24h"
        case .thirtyDays: return "7d"
        case .ninetyDays: return "30d"
        }
    }

    private var trendDelta: Double {
        guard snapshots.count > 1 else { return 0 }
        let previousIndex = max(0, snapshots.count - 1 - trendWindowDays)
        let prev = Double(snapshots[previousIndex].exposureIndex)
        guard prev > 0 else { return 0 }
        let current = Double(latestSnapshot.exposureIndex)
        return ((current - prev) / prev) * 100
    }

    private var peakValue: Int {
        snapshots.map(\.exposureIndex).max() ?? latestSnapshot.exposureIndex
    }

    private var lowValue: Int {
        snapshots.map(\.exposureIndex).min() ?? latestSnapshot.exposureIndex
    }

    private var volatilityValue: Double {
        let values = snapshots.map { Double($0.exposureIndex) }
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(variance)
    }

    private var volatilityLabel: String {
        switch volatilityValue {
        case ..<4: return "Low"
        case ..<10: return "Moderate"
        default: return "High"
        }
    }

    private var monitoringLabel: String {
        switch viewModel.monitoringIndicator {
        case .live:
            return "Live"
        case .stale:
            return "Stale"
        case .degraded:
            return "Degraded"
        }
    }

    private var monitoringColor: Color {
        switch viewModel.monitoringIndicator {
        case .live:
            return ThemeTokens.Accent.green
        case .stale:
            return ThemeTokens.Text.secondary
        case .degraded:
            return ThemeTokens.Accent.critical
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                headerCard
                exposureOverTimeCard
                contributingFactorsCard
                methodologyCard
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.md)
            .padding(.bottom, DesignSystem.Spacing.xl)
        }
        .background(ThemeTokens.Background.base.ignoresSafeArea())
        .navigationTitle("Exposure Drilldown")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        DarkCard(contentPadding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Exposure Index")
                        .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                        .foregroundStyle(ThemeTokens.Text.primary)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(monitoringColor)
                            .frame(width: 6, height: 6)
                        Text(monitoringLabel)
                            .font(DesignSystem.Typography.meta.weight(.semibold))
                            .foregroundStyle(ThemeTokens.Text.secondary)
                    }
                }

                Text("\(latestSnapshot.exposureIndex)")
                    .font(DesignSystem.Typography.metricLarge)
                    .foregroundStyle(ThemeTokens.Text.primary)
                    .monospacedDigit()

                Text(latestSnapshot.tier.label)
                    .font(DesignSystem.Typography.body.weight(.semibold))
                    .foregroundStyle(latestSnapshot.tier.color)

                TrendChip(value: trendDelta, suffix: trendSuffix)
            }
        }
    }

    private var exposureOverTimeCard: some View {
        DarkCard(contentPadding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Exposure Over Time")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)

                Picker("Range", selection: $selectedRange) {
                    ForEach(RiskHistoryRange.allCases) { range in
                        Text(range.rawValue).tag(range)
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

                chartBlock
                    .frame(height: 170)

                HStack {
                    statCell(title: "Peak", value: "\(peakValue)")
                    statCell(title: "Low", value: "\(lowValue)")
                    statCell(title: "Volatility", value: "\(volatilityLabel) (\(String(format: "%.1f", volatilityValue)))")
                }
            }
        }
    }

    @ViewBuilder
    private var chartBlock: some View {
#if canImport(Charts)
        Chart {
            ForEach(snapshots) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Exposure", point.exposureIndex)
                )
                .foregroundStyle(ThemeTokens.Accent.intelligenceBlue)
                .lineStyle(.init(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis(.hidden)
        .chartPlotStyle { plotArea in
            plotArea
                .background(ThemeTokens.Card.innerSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
#else
        SparklineFallbackView(values: snapshots.map { Double($0.exposureIndex) })
            .frame(maxWidth: .infinity)
            .background(ThemeTokens.Card.innerSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
#endif
    }

    private var contributingFactorsCard: some View {
        DarkCard(contentPadding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Contributing Factors")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)

                ForEach(latestSnapshot.factors) { factor in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            NavigationLink {
                                FactorDetailView(viewModel: viewModel, factor: factor, snapshot: latestSnapshot)
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(factor.severityColor.opacity(0.85))
                                        .frame(width: 8, height: 8)
                                    Text(factor.name)
                                        .font(DesignSystem.Typography.body.weight(.semibold))
                                        .foregroundStyle(ThemeTokens.Text.primary)
                                    Spacer()
                                    Text("\(factor.value)")
                                        .font(DesignSystem.Typography.body.weight(.semibold))
                                        .foregroundStyle(ThemeTokens.Text.primary)
                                        .monospacedDigit()
                                    Text(deltaText(factor.delta24h))
                                        .font(DesignSystem.Typography.meta.weight(.semibold))
                                        .foregroundStyle(deltaColor(for: factor.delta24h, tier: latestSnapshot.tier))
                                        .monospacedDigit()
                                }
                            }
                            .buttonStyle(.plain)

                            Button {
                                toggleFactor(factor.id)
                            } label: {
                                Image(systemName: expandedFactorIDs.contains(factor.id) ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ThemeTokens.Text.secondary)
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.plain)
                        }

                        if expandedFactorIDs.contains(factor.id) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(whyMovedText(for: factor))
                                    .font(DesignSystem.Typography.meta)
                                    .foregroundStyle(ThemeTokens.Text.secondary)
                                Text(factor.weightPercentText)
                                    .font(DesignSystem.Typography.meta.weight(.semibold))
                                    .foregroundStyle(ThemeTokens.Text.primary)
                                Text("Confidence: \(confidenceLabel(for: factor.delta24h))")
                                    .font(DesignSystem.Typography.meta.weight(.semibold))
                                    .foregroundStyle(ThemeTokens.Text.secondary)
                            }
                            .padding(10)
                            .background(ThemeTokens.Card.innerSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                    .padding(.vertical, 4)

                    if factor.id != latestSnapshot.factors.last?.id {
                        Rectangle()
                            .fill(ThemeTokens.Card.divider)
                            .frame(height: 1)
                    }
                }
            }
        }
    }

    private var methodologyCard: some View {
        DarkCard(contentPadding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("How Exposure Index Is Calculated")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Text.primary)

                ForEach(RiskModel.transparentWeights, id: \.0) { item in
                    HStack {
                        Text(item.0)
                            .font(DesignSystem.Typography.body)
                            .foregroundStyle(ThemeTokens.Text.secondary)
                        Spacer()
                        Text("\(Int((item.1 * 100).rounded()))%")
                            .font(DesignSystem.Typography.body.weight(.semibold))
                            .foregroundStyle(ThemeTokens.Text.primary)
                            .monospacedDigit()
                    }
                }

                Text("Exposure Index is a weighted composite of risk surfaces and behavioral signals.")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(ThemeTokens.Text.secondary)
            }
        }
    }

    private func statCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DesignSystem.Typography.meta)
                .foregroundStyle(ThemeTokens.Text.secondary)
            Text(value)
                .font(DesignSystem.Typography.body.weight(.semibold))
                .foregroundStyle(ThemeTokens.Text.primary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleFactor(_ id: String) {
        if expandedFactorIDs.contains(id) {
            expandedFactorIDs.remove(id)
        } else {
            expandedFactorIDs.insert(id)
        }
    }

    private func deltaText(_ delta: Double) -> String {
        if delta == 0 { return "0.0%" }
        return String(format: "%@%.1f%%", delta > 0 ? "+" : "", delta)
    }

    private func deltaColor(for delta: Double, tier: ExposureTier) -> Color {
        if abs(delta) < 0.05 { return ThemeTokens.Text.secondary }
        if delta < 0 { return ThemeTokens.Accent.green }

        switch tier {
        case .guarded, .stable:
            return ThemeTokens.Accent.elevated
        case .elevated, .critical:
            return ThemeTokens.Accent.critical
        }
    }

    private func confidenceLabel(for delta: Double) -> String {
        let value = abs(delta)
        if value < 0.3 { return "Low" }
        if value <= 1.0 { return "Medium" }
        return "High"
    }

    private func whyMovedText(for factor: ExposureFactor) -> String {
        switch factor.id {
        case "contract_risk":
            return "Why this moved: New contract interactions increased assessed risk concentration."
        case "system_integrity_inverse":
            return "Why this moved: System integrity controls weakened across recent interactions."
        case "interaction_velocity":
            return "Why this moved: Transaction timing and pattern velocity diverged from baseline behavior."
        case "asset_volatility":
            return "Why this moved: Asset movement variance increased volatility contribution."
        default:
            return "Why this moved: Counterparty concentration shifted across recent interactions."
        }
    }
}

private struct SparklineFallbackView: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let points = normalizedPoints(in: proxy.size)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() {
                    path.addLine(to: point)
                }
            }
            .stroke(ThemeTokens.Accent.intelligenceBlue, style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round))
        }
        .padding(10)
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let range = max(maxValue - minValue, 1)
        return values.enumerated().map { idx, value in
            let x = size.width * CGFloat(idx) / CGFloat(max(values.count - 1, 1))
            let yNorm = (value - minValue) / range
            let y = size.height * CGFloat(1 - yNorm)
            return CGPoint(x: x, y: y)
        }
    }
}
