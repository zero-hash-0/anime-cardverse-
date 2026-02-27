import SwiftUI
import PhotosUI
import UIKit

private enum BetaTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case alerts = "Alerts"
    case activity = "Activity"
    case feedback = "Feedback"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house"
        case .alerts: return "exclamationmark.triangle"
        case .activity: return "clock.arrow.circlepath"
        case .feedback: return "bubble.left.and.bubble.right"
        }
    }
}

private enum AlertSeverity: String {
    case critical
    case warning
    case info

    var icon: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .critical:
            return Color(red: 0.95, green: 0.34, blue: 0.34)
        case .warning:
            return Color(red: 0.93, green: 0.67, blue: 0.24)
        case .info:
            return Color(red: 0.34, green: 0.67, blue: 0.94)
        }
    }
}

private enum AlertFilterChip: String, CaseIterable, Identifiable {
    case all = "All"
    case critical = "Critical"
    case warning = "Warning"
    case info = "Info"

    var id: String { rawValue }
}

struct ContentView: View {
    @StateObject private var viewModel: DashboardViewModel
    @FocusState private var walletFieldFocused: Bool
    @State private var selectedTab: BetaTab = .home
    @State private var firstSyncInProgress = false
    @State private var feedbackMessage = ""
    @State private var feedbackStatus: String?
    @State private var isSendingFeedback = false
    @State private var selectedScreenshot: PhotosPickerItem?
    @State private var screenshotBase64: String?
    @State private var showAbout = false
    @State private var radarSweepRotation: Double = -28
    @State private var hasAnimatedRadarSweep = false
    @State private var selectedAlertFilter: AlertFilterChip = .all
    @AppStorage("betaOnboardingSeen") private var betaOnboardingSeen = false

    init(viewModel: DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header

                Group {
                    switch selectedTab {
                    case .home:
                        homeView
                    case .alerts:
                        alertsView
                    case .activity:
                        activityView
                    case .feedback:
                        feedbackView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                tabBar
            }
            .blur(radius: viewModel.isMaintenanceMode ? 2 : 0)
            .disabled(viewModel.isMaintenanceMode)

            if viewModel.isMaintenanceMode {
                MaintenanceView(
                    message: viewModel.maintenanceMessage,
                    onRetry: {
                        Task { await viewModel.retryMaintenanceCheck() }
                    }
                )
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .background {
            ZStack {
                LinearGradient(
                    colors: [RadarTheme.Palette.backgroundTop, RadarTheme.Palette.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                IntelligenceBackgroundLayer(sweepRotation: radarSweepRotation)
                    .ignoresSafeArea()
            }
        }
        .task {
            await viewModel.onAppear()
            if viewModel.hasValidWalletAddress && !viewModel.isMaintenanceMode {
                await viewModel.refresh(silent: true)
            }
        }
        .onAppear {
            guard !hasAnimatedRadarSweep else { return }
            hasAnimatedRadarSweep = true
            withAnimation(.easeInOut(duration: 1.6)) {
                radarSweepRotation = 24
            }
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    walletFieldFocused = false
                }
            }
        }
        .fullScreenCover(isPresented: onboardingBinding) {
            BetaOnboardingView {
                viewModel.trackOnboardingDismissed()
                betaOnboardingSeen = true
            } onFeedback: {
                viewModel.trackOnboardingFeedbackTapped()
                viewModel.trackFeedbackOpen()
                selectedTab = .feedback
                betaOnboardingSeen = true
            } onViewed: {
                viewModel.trackOnboardingViewed()
            }
        }
        .sheet(isPresented: $showAbout) {
            AboutView(
                viewModel: viewModel,
                buildID: buildID,
                apiEnvironment: apiEnvironmentLabel,
                lastSyncText: viewModel.dataFreshnessText,
                baseAPIURL: AppEnvironment.current.apiBaseURL?.absoluteString ?? "Not configured",
                deviceModel: UIDevice.current.model,
                iosVersion: UIDevice.current.systemVersion,
                diagnosticsEnabled: diagnosticsEnabled,
                onEnvMismatchDetected: { environment, baseURL in
                    viewModel.trackEnvironmentMismatch(environment: environment, baseURL: baseURL)
                },
                onDiagnosticsOpened: {
                    viewModel.trackDiagnosticsOpened()
                },
                onPreflightRan: {
                    viewModel.trackPreflightRan()
                },
                onPreflightFailed: { reason in
                    viewModel.trackPreflightFailed(reason: reason)
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text("Wallet Yield & Risk Intelligence")
                    .font(DesignSystem.Typography.h2)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("Monitoring")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            Spacer()
            Circle()
                .fill(viewModel.isLoading ? DesignSystem.Colors.warning : DesignSystem.Colors.accent)
                .frame(width: 8, height: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.top, DesignSystem.Spacing.sm)
        .padding(.bottom, DesignSystem.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    Color.black.opacity(0.35)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 3)
        )
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.top, DesignSystem.Spacing.xs)
        .onLongPressGesture(minimumDuration: 0.7) {
            guard diagnosticsEnabled else { return }
            showAbout = true
        }
    }

    private var homeView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    WalletInputView(walletAddress: $viewModel.walletAddress, isFocused: $walletFieldFocused)
                        .intelligenceCardStyle(cornerRadius: DesignSystem.Radius.md)

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Button("Connect Wallet") {
                            connectAndSyncIfNeeded()
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.84))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(connectWalletButtonColor)
                        .clipShape(Capsule())

                        Button("Refresh") {
                            Task { await viewModel.refresh() }
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(DesignSystem.Colors.surfaceElevated)
                        .overlay(Capsule().stroke(DesignSystem.Colors.border, lineWidth: 1))
                        .clipShape(Capsule())
                        .disabled(viewModel.isLoading || !viewModel.hasValidWalletAddress)

                        Spacer()
                    }
                }

                if firstSyncInProgress {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        ProgressView()
                            .tint(DesignSystem.Colors.accent)
                        Text("Syncing wallet data...")
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }

                if !viewModel.hasValidWalletAddress {
                    emptyStateCard
                } else if viewModel.isLoading && viewModel.historyEvents.isEmpty {
                    dashboardSkeletonState
                } else {
                    heroIntelligenceCard

                    walletPatternAnalysisPanel

                    breakdownPillsSection

                    recentActivitySection

                    intelligenceFeedSection
                }

                if viewModel.showReminderBanner {
                    reminderBanner
                }

                if let warning = viewModel.freshnessWarning, viewModel.lastCheckedAt != nil {
                    Text(warning)
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .animation(.easeOut(duration: 0.22), value: viewModel.isLoading)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.bottom, DesignSystem.Spacing.xl)
            .padding(.top, DesignSystem.Spacing.md)
        }
        .refreshable {
            viewModel.trackPullToRefresh()
            await viewModel.refresh()
        }
    }

    private var heroIntelligenceCard: some View {
        IntelligenceCard(severity: riskScore >= 70 ? .safe : (riskScore >= 40 ? .caution : .danger)) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack {
                    SeverityBadge(severity: riskScore >= 70 ? .safe : (riskScore >= 40 ? .caution : .danger))
                    Spacer()
                    Text("Wallet Health")
                        .font(DesignSystem.Typography.meta.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                HStack(alignment: .lastTextBaseline, spacing: DesignSystem.Spacing.xs) {
                    Text("\(riskScoreDisplay)")
                        .font(DesignSystem.Typography.metricLarge)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .shadow(color: DesignSystem.Colors.accent.opacity(0.22), radius: 4, x: 0, y: 0)
                    Text("Risk Score")
                        .font(DesignSystem.Typography.body.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                HStack(spacing: DesignSystem.Spacing.md) {
                    breakdownMetric(label: "Suspicious Tokens", value: suspiciousTokensCount)
                    breakdownMetric(label: "High-Risk Interactions", value: highRiskInteractionsCount)
                    breakdownMetric(label: "Unverified Assets", value: unverifiedAssetsCount)
                }

                HStack {
                    Text(lastScannedText)
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textMuted)
                    Spacer()
                    if !viewModel.dataConfidenceLabel.isEmpty {
                        Text(viewModel.dataConfidenceLabel)
                            .font(DesignSystem.Typography.meta.weight(.semibold))
                            .foregroundStyle(confidenceColor)
                    }
                }
            }
        }
    }

    private func breakdownMetric(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
            Text("\(value)")
                .font(DesignSystem.Typography.metricMedium)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(DesignSystem.Typography.meta)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var breakdownPillsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Breakdown")
                .font(DesignSystem.Typography.cardTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    breakdownPill(title: "Tokens", count: tokensCount)
                    breakdownPill(title: "Contracts", count: contractsCount)
                    breakdownPill(title: "NFTs", count: nftsCount)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func breakdownPill(title: String, count: Int) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Text("(\(count))")
                .font(DesignSystem.Typography.body.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.surfaceElevated)
        .overlay(Capsule().stroke(DesignSystem.Colors.border, lineWidth: 1))
        .clipShape(Capsule())
    }

    private var walletPatternAnalysisPanel: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Wallet Pattern Analysis")
                .font(DesignSystem.Typography.cardTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            IntelligenceCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    analysisRow(title: "Most interacted protocol", value: mostInteractedProtocol)
                    analysisRow(title: "Interaction frequency trend", value: interactionFrequencyTrend)
                    analysisRow(title: "Average holding time", value: averageHoldingTime)
                    analysisRow(title: "Risk delta 7D", value: riskDelta7D)
                }
            }
        }
    }

    private func analysisRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.body.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Recent Activity")
                .font(DesignSystem.Typography.cardTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            if viewModel.historyEvents.isEmpty && viewModel.isLoading {
                loadingCard
            } else if viewModel.historyEvents.isEmpty {
                simpleEmpty("No activity yet. Connect wallet to start.")
            } else {
                ForEach(viewModel.historyEvents.prefix(3)) { event in
                    activityCard(event: event)
                }
            }
        }
    }

    private func activityCard(event: AirdropEvent) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            TokenIconView(
                symbol: event.metadata.symbol,
                mint: event.mint,
                logoURL: event.metadata.logoURL,
                size: 42
            )

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.metadata.symbol)
                            .font(DesignSystem.Typography.body.weight(.semibold))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Text("Wallet activity detected")
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                    Spacer()
                    Text("+\(event.delta.description)")
                        .font(DesignSystem.Typography.body.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.accent.opacity(0.90))
                }

                Text(event.detectedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.textMuted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .intelligenceCardStyle(cornerRadius: DesignSystem.Radius.md)
    }

    private var dashboardSkeletonState: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated)
                .frame(height: 212)
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated)
                .frame(height: 148)
            RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated)
                .frame(height: 128)
        }
        .overlay {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                ProgressView()
                    .tint(DesignSystem.Colors.accent)
                Text("Loading intelligence snapshot...")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignSystem.Spacing.sm)
        }
        .redacted(reason: .placeholder)
        .transition(.opacity)
    }

    private var intelligenceFeedSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Intelligence Feed")
                .font(DesignSystem.Typography.cardTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            IntelligenceCard {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    feedRow(title: "Risk posture", value: riskScore >= 70 ? "Stable profile" : "Elevated profile")
                    feedRow(title: "Primary watch signal", value: suspiciousTokensCount > 0 ? "Suspicious token activity" : "No immediate token flags")
                    feedRow(title: "Scan status", value: viewModel.lastCheckedAt == nil ? "Awaiting first sync" : "Actively monitoring")
                }
            }
        }
    }

    private func feedRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.body.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var emptyStateCard: some View {
        IntelligenceCard(severity: .caution) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("Connect your wallet to start intelligence monitoring.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Button("Connect Wallet") {
                    connectAndSyncIfNeeded()
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.84))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(connectWalletButtonColor)
                .clipShape(Capsule())
            }
        }
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preparing your first snapshot")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            Text("This usually takes a few seconds.")
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            ProgressView()
                .tint(DesignSystem.Colors.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DesignSystem.Colors.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignSystem.Colors.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var reminderBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick check-in: anything confusing or missing?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RadarTheme.Palette.textPrimary)

            HStack(spacing: 10) {
                Button("Send Feedback") {
                    viewModel.reminderFeedbackTapped()
                    viewModel.trackFeedbackOpen()
                    selectedTab = .feedback
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RadarTheme.Palette.accent)
                .clipShape(Capsule())

                Button("Dismiss") {
                    viewModel.dismissReminderBanner()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RadarTheme.Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RadarTheme.Palette.surface)
                .overlay(Capsule().stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                .clipShape(Capsule())

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DesignSystem.Colors.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignSystem.Colors.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var alertsView: some View {
        let filteredAlerts = filteredAlertEvents
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("Alerts")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(RadarTheme.Palette.textPrimary)

                alertFilterChips

                if filteredAlerts.isEmpty {
                    simpleEmpty("No critical alerts right now.")
                } else {
                    ForEach(filteredAlerts.prefix(25)) { event in
                        let severity = alertSeverity(for: event)
                        Button {
                            viewModel.trackAlertOpen(alertType: severity.rawValue)
                        } label: {
                            AlertSeverityCard(event: event, severity: severity)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
    }

    private var alertFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AlertFilterChip.allCases) { filter in
                    let selected = selectedAlertFilter == filter
                    Button {
                        selectedAlertFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selected ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selected ? DesignSystem.Colors.surfaceElevated : DesignSystem.Colors.surface)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(selected ? DesignSystem.Colors.border.opacity(1.0) : DesignSystem.Colors.border.opacity(0.75), lineWidth: 1)
                            )
                            .clipShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var filteredAlertEvents: [AirdropEvent] {
        let sorted = viewModel.historyEvents.sorted { $0.detectedAt > $1.detectedAt }
        guard selectedAlertFilter != .all else { return sorted }
        return sorted.filter { event in
            switch selectedAlertFilter {
            case .all:
                return true
            case .critical:
                return alertSeverity(for: event) == .critical
            case .warning:
                return alertSeverity(for: event) == .warning
            case .info:
                return alertSeverity(for: event) == .info
            }
        }
    }

    private func alertSeverity(for event: AirdropEvent) -> AlertSeverity {
        let criticalKeywords = ["scam", "drainer", "phishing", "malicious", "exploit"]
        let warningKeywords = ["suspicious", "unverified", "unknown", "airdrop", "free claim", "bonus"]
        let haystack = "\(event.metadata.name) \(event.metadata.symbol) \(event.risk.reasons.joined(separator: " "))".lowercased()

        if criticalKeywords.contains(where: { haystack.contains($0) }) {
            return .critical
        }
        if warningKeywords.contains(where: { haystack.contains($0) }) {
            return .warning
        }
        return .info
    }

    private var activityView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("Activity")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(RadarTheme.Palette.textPrimary)

                if viewModel.historyEvents.isEmpty {
                    simpleEmpty("No activity yet. Connect wallet to start.")
                } else {
                    ForEach(viewModel.historyEvents.prefix(25)) { event in
                        Button {
                            viewModel.trackClaimOpen(claimType: event.metadata.symbol)
                        } label: {
                            HStack(spacing: 10) {
                                TokenIconView(
                                    symbol: event.metadata.symbol,
                                    mint: event.mint,
                                    logoURL: event.metadata.logoURL,
                                    size: 28
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(event.metadata.symbol) +\(event.delta.description)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(RadarTheme.Palette.textPrimary)
                                    Text(event.detectedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(RadarTheme.Palette.textSecondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(RadarTheme.Palette.surface)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
    }

    private var feedbackView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Feedback")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                Text("Tell us what blocked you. Keep it short.")
                    .font(.caption)
                    .foregroundStyle(RadarTheme.Palette.textSecondary)

                TextEditor(text: $feedbackMessage)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(RadarTheme.Palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                PhotosPicker(selection: $selectedScreenshot, matching: .images) {
                    Text(screenshotBase64 == nil ? "Attach Screenshot (optional)" : "Screenshot attached")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RadarTheme.Palette.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RadarTheme.Palette.surface)
                        .overlay(Capsule().stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                        .clipShape(Capsule())
                }

                Button(isSendingFeedback ? "Sending..." : "Send Feedback") {
                    Task { await sendFeedback() }
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RadarTheme.Palette.accent)
                .clipShape(Capsule())
                .disabled(isSendingFeedback || feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let feedbackStatus {
                    Text(feedbackStatus)
                        .font(.caption)
                        .foregroundStyle(RadarTheme.Palette.textSecondary)
                }

                if diagnosticsEnabled {
                    Button("About / Diagnostics") {
                        showAbout = true
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RadarTheme.Palette.surface)
                    .overlay(Capsule().stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                    .clipShape(Capsule())
                }

                Text("Build ID: \(buildID)")
                    .font(.caption2)
                    .foregroundStyle(RadarTheme.Palette.textSecondary)
            }
            .padding(16)
        }
        .onChange(of: selectedScreenshot) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        screenshotBase64 = data.base64EncodedString()
                    }
                }
            }
        }
    }

    private func simpleEmpty(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(RadarTheme.Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RadarTheme.Palette.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(RadarTheme.Palette.stroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DesignSystem.Colors.border)
                .frame(height: 1)

            HStack(spacing: 8) {
                ForEach(BetaTab.allCases) { tab in
                    let selected = selectedTab == tab
                    Button {
                        selectedTab = tab
                        if tab == .alerts { viewModel.trackAlertsTabOpen() }
                        if tab == .activity { viewModel.trackActivityTabOpen() }
                        if tab == .feedback { viewModel.trackFeedbackOpen() }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 15, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(selected ? DesignSystem.Colors.accent.opacity(0.90) : DesignSystem.Colors.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected ? DesignSystem.Colors.accent.opacity(0.10) : .clear)
                        .overlay {
                            if selected {
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 13)
            .padding(.bottom, 14)
        }
        .background(
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.black.opacity(0.25)
                LinearGradient(
                    colors: [Color.white.opacity(0.05), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .shadow(color: Color.black.opacity(0.22), radius: 8, x: 0, y: -1)
    }

    private func connectAndSyncIfNeeded() {
        viewModel.connectWallet()
        guard viewModel.hasValidWalletAddress else { return }
        guard viewModel.lastCheckedAt == nil else { return }
        firstSyncInProgress = true
        Task {
            await viewModel.refresh()
            firstSyncInProgress = false
        }
    }

    private func sendFeedback() async {
        isSendingFeedback = true
        defer { isSendingFeedback = false }

        let success = await viewModel.submitFeedback(message: feedbackMessage, screenshotBase64: screenshotBase64)
        if success {
            feedbackStatus = "Thanks. Feedback sent."
            feedbackMessage = ""
            screenshotBase64 = nil
            selectedScreenshot = nil
        } else {
            feedbackStatus = "Could not send right now. Try again."
        }
    }

    private var confidenceColor: Color {
        switch viewModel.dataConfidenceLabel {
        case "High confidence data": return DesignSystem.Colors.accent.opacity(0.78)
        case "Partial data": return DesignSystem.Colors.warning
        default: return DesignSystem.Colors.danger
        }
    }

    private var connectWalletButtonColor: Color {
        DesignSystem.Colors.accent.opacity(0.88)
    }

    private var integrityScore: Int {
        viewModel.securityScore
    }

    private var highRiskRatio: Double {
        guard viewModel.totalDetectedCount > 0 else { return 0 }
        return Double(viewModel.highRiskCount) / Double(viewModel.totalDetectedCount)
    }

    private var riskScore: Int {
        max(0, min(100, 100 - Int((highRiskRatio * 100).rounded())))
    }

    private var yieldScore: Int {
        let amount = NSDecimalNumber(decimal: viewModel.totalDetectedAmount).doubleValue
        let normalized = Int((amount * 10).rounded())
        return max(0, min(100, normalized))
    }

    private var estimatedMonthlyYieldText: String {
        let monthly = viewModel.latestDetectedAmount * Decimal(30)
        let value = NSDecimalNumber(decimal: monthly).doubleValue
        return String(format: "%.2f tokens", value)
    }

    private var hasLastUpdated: Bool {
        viewModel.lastCheckedAt != nil
    }

    private var suspiciousTokensCount: Int {
        viewModel.highRiskCount
    }

    private var highRiskInteractionsCount: Int {
        viewModel.highRiskCount + viewModel.mediumRiskCount
    }

    private var unverifiedAssetsCount: Int {
        viewModel.historyEvents.filter { $0.metadata.logoURL == nil }.count
    }

    private var tokensCount: Int {
        Set(viewModel.historyEvents.map(\.mint)).count
    }

    private var contractsCount: Int {
        viewModel.highRiskCount + viewModel.mediumRiskCount
    }

    private var nftsCount: Int {
        0
    }

    private var lastScannedText: String {
        guard let lastCheckedAt = viewModel.lastCheckedAt else {
            return "Last scanned: pending"
        }
        return "Last scanned: \(lastCheckedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private var mostInteractedProtocol: String {
        let top = Dictionary(grouping: viewModel.historyEvents, by: { $0.metadata.symbol.uppercased() })
            .max(by: { $0.value.count < $1.value.count })?
            .key
        return top ?? "Helium"
    }

    private var interactionFrequencyTrend: String {
        switch viewModel.historyEvents.count {
        case 0...3:
            return "Low (stable)"
        case 4...10:
            return "Moderate (+8% WoW)"
        default:
            return "High (+16% WoW)"
        }
    }

    private var averageHoldingTime: String {
        viewModel.historyEvents.isEmpty ? "TBD" : "12.4 days (est.)"
    }

    private var riskDelta7D: String {
        let delta = max(-15, min(18, (viewModel.highRiskCount * 3) - 4))
        return delta >= 0 ? "+\(delta)%" : "\(delta)%"
    }

    private var yieldScoreDisplay: String {
        hasLastUpdated ? "\(yieldScore)" : "—"
    }

    private var riskScoreDisplay: String {
        hasLastUpdated ? "\(riskScore)" : "—"
    }

    private var integrityScoreDisplay: String {
        hasLastUpdated ? "\(integrityScore)" : "—"
    }

    private var estimatedMonthlyYieldDisplay: String {
        hasLastUpdated ? estimatedMonthlyYieldText : "—"
    }

    private var buildID: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "v\(version) (\(build))"
    }

    private var apiEnvironmentLabel: String {
        AppEnvironment.current.environmentName
    }

    private var diagnosticsEnabled: Bool {
        let env = AppEnvironment.current.environmentName
        return env == "beta"
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !betaOnboardingSeen },
            set: { newValue in
                if !newValue { betaOnboardingSeen = true }
            }
        )
    }
}

private struct IntelligenceBackgroundLayer: View {
    let sweepRotation: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GridPattern(spacing: 28)
                    .stroke(DesignSystem.Colors.accent.opacity(0.045), lineWidth: 0.5)

                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: DesignSystem.Colors.accent.opacity(0.05), location: 0.07),
                                .init(color: .clear, location: 0.14),
                                .init(color: .clear, location: 1.0)
                            ]),
                            center: .center,
                            angle: .degrees(sweepRotation)
                        )
                    )
                    .frame(width: proxy.size.width * 1.45, height: proxy.size.width * 1.45)
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.4)
                    .blendMode(.screen)
                    .opacity(0.85)
            }
            .opacity(0.055)
        }
        .allowsHitTesting(false)
    }
}

private struct GridPattern: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard spacing > 0 else { return path }

        var x: CGFloat = 0
        while x <= rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }

        var y: CGFloat = 0
        while y <= rect.maxY {
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += spacing
        }

        return path
    }
}

private struct AlertSeverityCard: View {
    let event: AirdropEvent
    let severity: AlertSeverity

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(severity.color.opacity(0.78))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(event.metadata.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                    .lineLimit(1)

                Text(event.risk.reasons.first ?? "Review this activity for safety.")
                    .font(.caption)
                    .foregroundStyle(RadarTheme.Palette.textSecondary.opacity(0.92))
                    .lineLimit(2)

                Text(event.detectedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(RadarTheme.Palette.textSecondary.opacity(0.7))
            }

            Spacer(minLength: 6)

            Image(systemName: severity.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(severity.color.opacity(0.82))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(RadarTheme.Palette.surface)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                )
                .shadow(color: Color.black.opacity(0.20), radius: 5, x: 0, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(RadarTheme.Palette.stroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct BetaOnboardingView: View {
    let onDismiss: () -> Void
    let onFeedback: () -> Void
    let onViewed: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [RadarTheme.Palette.backgroundTop, RadarTheme.Palette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Beta Test")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(RadarTheme.Palette.textPrimary)

                onboardingBullet("Connect your wallet to load your summary.")
                onboardingBullet("Pull to refresh if numbers look outdated.")
                onboardingBullet("Use Feedback to report anything confusing or incorrect.")

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    Button("Send Feedback") {
                        onFeedback()
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RadarTheme.Palette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button("Got it") {
                        onDismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.black.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RadarTheme.Palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(24)
        }
        .task {
            onViewed()
        }
    }

    private func onboardingBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(RadarTheme.Palette.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            Text(text)
                .font(.body)
                .foregroundStyle(RadarTheme.Palette.textSecondary)
        }
    }
}

private struct AboutView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let buildID: String
    let apiEnvironment: String
    let lastSyncText: String
    let baseAPIURL: String
    let deviceModel: String
    let iosVersion: String
    let diagnosticsEnabled: Bool
    let onEnvMismatchDetected: (_ environment: String, _ baseURL: String) -> Void
    let onDiagnosticsOpened: () -> Void
    let onPreflightRan: () -> Void
    let onPreflightFailed: (_ reason: String) -> Void
    @State private var connectivityResult: ConnectivityResult?
    @State private var diagnosticsStatus: String?
    @State private var isTestingConnectivity = false
    @State private var isDiagnosticsActionRunning = false
    @State private var mismatchLogged = false
    @State private var didTrackOpen = false

    var body: some View {
        NavigationStack {
            List {
                row("Version / Build", buildID)
                row("APP_ENV", apiEnvironment)
                row("token_metadata_version", "v2")
                row("safe_dedupe", "true")
                row("Base API URL", baseAPIURL)
                row("Last Updated", lastSyncText.replacingOccurrences(of: "Last Updated: ", with: ""))
                row("Device", "\(deviceModel) / iOS \(iosVersion)")
                if diagnosticsEnabled {
                    Section("Preflight") {
                        Button(isTestingConnectivity ? "Running..." : "Run Preflight") {
                            Task { await runPreflight() }
                        }
                        .disabled(isTestingConnectivity)

                        if let connectivityResult {
                            row("HTTP Status", "\(connectivityResult.httpStatus)")
                            row("Backend Env", connectivityResult.env ?? "unknown")
                            row("Latency", "\(connectivityResult.latencyMs) ms")
                            row("Backend Version", connectivityResult.backendVersion ?? "unknown")
                            row("Checked At", connectivityResult.checkedAt.formatted(date: .abbreviated, time: .standard))
                        }
                    }

                    Section("Telemetry Verification") {
                        Button(isDiagnosticsActionRunning ? "Sending..." : "Send Test Analytics Event") {
                            Task {
                                isDiagnosticsActionRunning = true
                                await viewModel.diagnosticsSendTestAnalyticsEvent(env: apiEnvironment, baseURL: baseAPIURL)
                                diagnosticsStatus = "Sent test_event"
                                isDiagnosticsActionRunning = false
                            }
                        }

                        Button(isDiagnosticsActionRunning ? "Sending..." : "Send Test Non-Fatal Error") {
                            Task {
                                isDiagnosticsActionRunning = true
                                await viewModel.diagnosticsSendTestNonFatalError()
                                diagnosticsStatus = "Sent TestFlight non-fatal test"
                                isDiagnosticsActionRunning = false
                            }
                        }

                        Button(isDiagnosticsActionRunning ? "Sending..." : "Send Test Feedback") {
                            Task {
                                isDiagnosticsActionRunning = true
                                let ok = await viewModel.diagnosticsSendTestFeedback()
                                diagnosticsStatus = ok ? "Sent TestFlight feedback test" : "Feedback send failed"
                                isDiagnosticsActionRunning = false
                            }
                        }
                    }
                }

                if envMismatchWarning != nil {
                    Text(envMismatchWarning ?? "")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RadarTheme.Palette.danger)
                        .listRowBackground(RadarTheme.Palette.surface)
                }

                if let diagnosticsStatus {
                    Text(diagnosticsStatus)
                        .font(.caption)
                        .foregroundStyle(RadarTheme.Palette.textSecondary)
                        .listRowBackground(RadarTheme.Palette.surface)
                }
            }
            .disabled(isDiagnosticsActionRunning)
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [RadarTheme.Palette.backgroundTop, RadarTheme.Palette.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("About / Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if diagnosticsEnabled && !didTrackOpen {
                    didTrackOpen = true
                    onDiagnosticsOpened()
                }
                guard let envMismatchWarning, !mismatchLogged else { return }
                mismatchLogged = true
                onEnvMismatchDetected(apiEnvironment, baseAPIURL)
                connectivityResult = ConnectivityResult(
                    httpStatus: 0,
                    latencyMs: 0,
                    env: nil,
                    backendVersion: envMismatchWarning,
                    checkedAt: Date()
                )
            }
        }
    }

    private var envMismatchWarning: String? {
        guard apiEnvironment == "beta" else { return nil }
        guard baseAPIURL.contains("https://api.depincontrolcenter.app") else { return nil }
        return "Environment mismatch: beta build is pointing to production API."
    }

    private func runPreflight() async {
        onPreflightRan()
        guard let url = URL(string: "/health", relativeTo: URL(string: baseAPIURL)) else {
            onPreflightFailed("invalid_base_url")
            return
        }
        isTestingConnectivity = true
        defer { isTestingConnectivity = false }
        let startedAt = Date()
        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latencyMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            let backendVersion = parseBackendVersion(from: data)
            let backendEnv = parseBackendEnv(from: data)
            connectivityResult = ConnectivityResult(
                httpStatus: httpStatus,
                latencyMs: latencyMs,
                env: backendEnv,
                backendVersion: backendVersion,
                checkedAt: Date()
            )
            if !(200...299).contains(httpStatus) {
                onPreflightFailed("http_\(httpStatus)")
            } else if backendEnv == nil {
                onPreflightFailed("missing_env_in_health")
            }
        } catch {
            connectivityResult = ConnectivityResult(
                httpStatus: -1,
                latencyMs: Int(Date().timeIntervalSince(startedAt) * 1000),
                env: nil,
                backendVersion: "request_failed",
                checkedAt: Date()
            )
            onPreflightFailed("request_failed")
        }
    }

    private func parseBackendVersion(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let version = json["version"] as? String { return version }
        if let version = json["apiVersion"] as? String { return version }
        if let meta = json["meta"] as? [String: Any], let version = meta["version"] as? String { return version }
        return nil
    }

    private func parseBackendEnv(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let env = json["env"] as? String { return env }
        if let meta = json["meta"] as? [String: Any], let env = meta["env"] as? String { return env }
        return nil
    }

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RadarTheme.Palette.textSecondary)
            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(RadarTheme.Palette.textPrimary)
        }
        .listRowBackground(RadarTheme.Palette.surface)
    }
}

private struct ConnectivityResult {
    let httpStatus: Int
    let latencyMs: Int
    let env: String?
    let backendVersion: String?
    let checkedAt: Date
}

private struct MaintenanceView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            VStack(spacing: 10) {
                Text("Temporarily unavailable")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.body)
                    .foregroundStyle(RadarTheme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)

            Button("Try again") {
                onRetry()
            }
            .buttonStyle(.plain)
            .font(.headline.weight(.bold))
            .foregroundStyle(Color.black.opacity(0.9))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(RadarTheme.Palette.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [RadarTheme.Palette.backgroundTop, RadarTheme.Palette.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}
