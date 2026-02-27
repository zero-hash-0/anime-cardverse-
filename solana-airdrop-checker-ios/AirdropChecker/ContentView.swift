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
        case .home: return "rectangle.3.group"
        case .alerts: return "exclamationmark.shield"
        case .activity: return "chart.line.uptrend.xyaxis"
        case .feedback: return "questionmark.bubble"
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
    @State private var isRefreshing = false
    @State private var isConnectingWallet = false
    @State private var didJustConnect = false
    @State private var walletConnectStatus: WalletConnectStatus?
    @State private var connectButtonPulse = false
    @State private var didApplyLaunchTab = false
    @AppStorage("betaOnboardingSeen") private var betaOnboardingSeen = false

    init(viewModel: DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header

                ZStack {
                    switch selectedTab {
                    case .home:
                        homeView
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                )
                            )

                    case .alerts:
                        alertsView
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                )
                            )

                    case .activity:
                        activityView
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                )
                            )

                    case .feedback:
                        feedbackView
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                )
                            )
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tabBar
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
            if !didApplyLaunchTab, let launchTab = launchSelectedTab {
                selectedTab = launchTab
                didApplyLaunchTab = true
            }
            guard !hasAnimatedRadarSweep else { return }
            hasAnimatedRadarSweep = true
            withAnimation(.easeInOut(duration: 1.6)) {
                radarSweepRotation = 24
            }
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: isConnectingWallet) { connecting in
            if connecting {
                connectButtonPulse = true
            } else {
                connectButtonPulse = false
            }
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
            MonitoringDot()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.top, DesignSystem.Spacing.sm)
        .padding(.bottom, DesignSystem.Spacing.xs)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.25)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1),
            alignment: .top
        )
        .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 6)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.sm, style: .continuous))
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
                    WalletInputView(
                        walletAddress: $viewModel.walletAddress,
                        isFocused: $walletFieldFocused,
                        walletConnectStatus: nil,
                        walletErrorMessage: nil
                    )
                        .intelligenceCardStyle(cornerRadius: DesignSystem.Radius.md)

                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Button {
                            Task { await connectAndSyncIfNeeded() }
                        } label: {
                            connectWalletButtonLabel
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.black.opacity(0.84))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background {
                            ZStack {
                                if isConnectingWallet {
                                    Capsule()
                                        .fill(connectWalletButtonColor.opacity(0.22))
                                        .scaleEffect(connectButtonPulse ? 1.06 : 0.98)
                                        .opacity(connectButtonPulse ? 0.24 : 0.12)
                                        .animation(
                                            .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                                            value: connectButtonPulse
                                        )
                                }
                                Capsule()
                                    .fill(connectWalletButtonColor)
                            }
                        }
                        .clipShape(Capsule())
                        .disabled(isConnectingWallet)
                        .opacity(isConnectingWallet ? 0.92 : 1.0)
                        .brightness(isConnectingWallet ? -0.04 : 0)
                        .animation(.easeInOut(duration: 0.2), value: isConnectingWallet)
                        .buttonStyle(ConnectWalletButtonStyle())

                        Button("Refresh") {
                            Haptic.medium()
                            Task { await performRefresh() }
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(DesignSystem.Colors.surfaceElevated)
                        .overlay(Capsule().stroke(DesignSystem.Colors.border, lineWidth: 1))
                        .clipShape(Capsule())
                        .disabled(isRefreshing || isConnectingWallet || viewModel.isLoading || !viewModel.hasValidWalletAddress)
                        .opacity(isRefreshing ? 0.6 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isRefreshing)

                        Spacer()
                    }

                    if let rowStatus = walletRowStatus {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            if rowStatus.showsProgress {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(DesignSystem.Colors.textSecondary)
                            } else {
                                Image(systemName: rowStatus.icon)
                            }
                            Text(rowStatus.message)
                        }
                        .font(DesignSystem.Typography.meta.weight(.medium))
                        .foregroundStyle(rowStatus.color)
                        .padding(.top, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: walletConnectStatus)
                .animation(.easeInOut(duration: 0.2), value: firstSyncInProgress)

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
            .opacity(isRefreshing ? 0.6 : 1)
            .animation(.easeInOut(duration: 0.2), value: isRefreshing)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.bottom, DesignSystem.Spacing.xl)
            .padding(.top, DesignSystem.Spacing.md)
        }
        .refreshable {
            viewModel.trackPullToRefresh()
            await performRefresh()
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
                    Group {
                        if hasLastUpdated {
                            Text("\(riskScore)")
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.25), value: riskScore)
                        } else {
                            Text("—")
                        }
                    }
                    .font(DesignSystem.Typography.metricLarge)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .shadow(color: DesignSystem.Colors.accent.opacity(0.22), radius: 4, x: 0, y: 0)
                    Text("Risk Score")
                        .font(DesignSystem.Typography.body.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                ProgressView(value: Double(riskScore), total: 100)
                    .tint(riskScore > 70 ? .green : riskScore > 40 ? .yellow : .red)
                    .scaleEffect(x: 1, y: 1.5, anchor: .center)

                Text(riskScore > 70 ? "Low Risk Profile" :
                     riskScore > 40 ? "Moderate Risk" :
                     "High Risk Exposure")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                StatTripletRow(
                    metrics: [
                        StatTripletRow.Metric(
                            label: "Suspicious Tokens",
                            valueText: hasLastUpdated ? "\(suspiciousTokensCount)" : "—"
                        ),
                        StatTripletRow.Metric(
                            label: "High-Risk Interactions",
                            valueText: hasLastUpdated ? "\(highRiskInteractionsCount)" : "—"
                        ),
                        StatTripletRow.Metric(
                            label: "Unverified Assets",
                            valueText: hasLastUpdated ? "\(unverifiedAssetsCount)" : "—"
                        )
                    ]
                )

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
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.25)
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1),
            alignment: .top
        )
        .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 6)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous))
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
                    breakdownPill(title: "NFTs", countText: nftPillCountText)
                        .onTapGesture {
                            guard viewModel.nftCountLoadState == .failure else { return }
                            Task { await performRefresh() }
                        }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func breakdownPill(title: String, count: Int) -> some View {
        breakdownPill(title: title, countText: "\(count)")
    }

    private func breakdownPill(title: String, countText: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Text("(\(countText))")
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
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.historyEvents.map(\.id))
    }

    private func activityCard(event: AirdropEvent) -> some View {
        let isPositive = event.delta >= 0
        return HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
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
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                            Text(formattedDelta(event.delta))
                        }
                        .font(DesignSystem.Typography.body.weight(.semibold))
                        .foregroundStyle(isPositive ? Color.green : Color.red)

                        Text("Est. \(estimatedUSDText(for: event))")
                            .font(DesignSystem.Typography.meta)
                            .foregroundStyle(DesignSystem.Colors.textMuted.opacity(0.72))
                    }
                }

                Text(event.detectedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.82))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
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
                    Label(
                        riskScore >= 70 ? "Stable profile" : "Elevated profile",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(DesignSystem.Typography.body.weight(.semibold))
                    .foregroundStyle(.green)

                    Label(
                        suspiciousTokensCount > 0 ? "Suspicious token activity" : "No immediate token flags",
                        systemImage: "exclamationmark.circle.fill"
                    )
                    .font(DesignSystem.Typography.body.weight(.semibold))
                    .foregroundStyle(.yellow)

                    Label(
                        viewModel.lastCheckedAt == nil ? "Awaiting first sync" : "Actively monitoring",
                        systemImage: "eye.circle.fill"
                    )
                    .font(DesignSystem.Typography.body.weight(.semibold))
                    .foregroundStyle(.blue)
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

                Button {
                    Task { await connectAndSyncIfNeeded() }
                } label: {
                    connectWalletButtonLabel
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.84))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(connectWalletButtonColor)
                .clipShape(Capsule())
                .disabled(isConnectingWallet)
                .opacity(isConnectingWallet ? 0.92 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isConnectingWallet)
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
                        let isPositive = event.delta >= 0
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
                                    HStack(spacing: 4) {
                                        Text(event.metadata.symbol)
                                        Image(systemName: isPositive ? "arrow.up.right" : "arrow.down.right")
                                        Text(formattedDelta(event.delta))
                                    }
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(RadarTheme.Palette.textPrimary)
                                    Text("Est. \(estimatedUSDText(for: event))")
                                        .font(.caption2)
                                        .foregroundStyle(RadarTheme.Palette.textSecondary.opacity(0.64))
                                    Text(event.detectedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(RadarTheme.Palette.textSecondary.opacity(0.82))
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(RadarTheme.Palette.surface)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.historyEvents.map(\.id))
            .padding(16)
        }
    }

    private func formattedDelta(_ delta: Decimal) -> String {
        let value = NSDecimalNumber(decimal: delta).doubleValue
        return String(format: "%@%.4g", value >= 0 ? "+" : "", value)
    }

    private func estimatedUSDText(for event: AirdropEvent) -> String {
        let symbol = event.metadata.symbol.uppercased()
        let priceHintBySymbol: [String: Double] = [
            "JUP": 1.00,
            "HNT": 7.50,
            "RNDR": 6.00
        ]
        guard let price = priceHintBySymbol[symbol] else { return "USD unavailable" }
        let delta = abs(NSDecimalNumber(decimal: event.delta).doubleValue)
        return String(format: "$%.2f", delta * price)
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
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.28),
                    Color.black.opacity(0.08),
                    .clear
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 14)

            HStack(spacing: 8) {
                ForEach(BetaTab.allCases) { tab in
                    let selected = selectedTab == tab
                    Button {
                        guard selectedTab != tab else { return }
                        Haptic.light()
                        selectedTab = tab
                        if tab == .alerts { viewModel.trackAlertsTabOpen() }
                        if tab == .activity { viewModel.trackActivityTabOpen() }
                        if tab == .feedback { viewModel.trackFeedbackOpen() }
                    } label: {
                        TabItemView(tab: tab, selected: selected)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 78)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.23, blue: 0.25),
                                Color(red: 0.15, green: 0.16, blue: 0.18)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.08), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.black.opacity(0.35), lineWidth: 3)
                            .blur(radius: 2.5)
                            .mask(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [.black, .clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                    )
                    .shadow(color: Color.black.opacity(0.52), radius: 22, x: 0, y: 12)
            )
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 10)
        }
        .background(
            Color.black.opacity(0.26)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func connectAndSyncIfNeeded() async {
        guard !isConnectingWallet else { return }
        isConnectingWallet = true
        withAnimation(.easeInOut(duration: 0.18)) {
            walletConnectStatus = .connecting
        }
        Haptic.light()
        defer { isConnectingWallet = false }

        viewModel.connectWallet()
        let start = Date()
        var connected = false

        while true {
            switch viewModel.connectionState {
            case .connected:
                connected = true
            case .error(let message):
                viewModel.errorMessage = message
                connected = false
            default:
                connected = false
            }

            if connected { break }
            if case .error = viewModel.connectionState { break }

            if Date().timeIntervalSince(start) > 8 {
                viewModel.errorMessage = "Connection timed out. Try again."
                break
            }

            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        guard connected else {
            withAnimation(.easeInOut(duration: 0.2)) {
                walletConnectStatus = .failure
            }
            return
        }

        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            didJustConnect = true
            walletConnectStatus = .success
        }
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    didJustConnect = false
                }
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                if walletConnectStatus == .success {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        walletConnectStatus = nil
                    }
                }
            }
        }

        guard viewModel.hasValidWalletAddress else { return }
        guard viewModel.lastCheckedAt == nil else { return }
        firstSyncInProgress = true
        await viewModel.refresh()
        firstSyncInProgress = false
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

    @MainActor
    private func performRefresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await viewModel.refresh()
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

    private var walletRowStatus: WalletRowStatus? {
        if firstSyncInProgress {
            return WalletRowStatus(
                message: "Syncing wallet data...",
                icon: "arrow.triangle.2.circlepath",
                color: DesignSystem.Colors.textSecondary,
                showsProgress: true
            )
        }

        switch walletConnectStatus {
        case .connecting:
            return WalletRowStatus(
                message: "Connecting to wallet...",
                icon: "link",
                color: DesignSystem.Colors.textSecondary,
                showsProgress: true
            )
        case .success:
            return WalletRowStatus(
                message: "Connected ✓",
                icon: "checkmark.circle.fill",
                color: DesignSystem.Colors.accent,
                showsProgress: false
            )
        case .failure:
            return WalletRowStatus(
                message: viewModel.errorMessage ?? "Connection failed. Try again.",
                icon: "exclamationmark.triangle.fill",
                color: DesignSystem.Colors.danger,
                showsProgress: false
            )
        case .none:
            if let checked = viewModel.lastCheckedAt {
                return WalletRowStatus(
                    message: "Last synced: \(checked.formatted(date: .omitted, time: .shortened))",
                    icon: "clock",
                    color: DesignSystem.Colors.textSecondary,
                    showsProgress: false
                )
            }
            return WalletRowStatus(
                message: "Ready",
                icon: "checkmark.seal",
                color: DesignSystem.Colors.textSecondary,
                showsProgress: false
            )
        }
    }

    @ViewBuilder
    private var connectWalletButtonLabel: some View {
        HStack(spacing: 6) {
            if isConnectingWallet {
                ProgressView()
                    .tint(Color.black.opacity(0.84))
                    .scaleEffect(0.85)
            } else if didJustConnect {
                Image(systemName: "checkmark.circle.fill")
            }

            Text(
                isConnectingWallet
                ? "Connecting..."
                : (didJustConnect ? "Connected" : "Connect Wallet")
            )
        }
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

    private var nftPillCountText: String {
        switch viewModel.nftCountLoadState {
        case .idle, .loading:
            return "—"
        case .success:
            return "\(viewModel.totalNFTCount)"
        case .failure:
            return "!"
        }
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

    private var launchSelectedTab: BetaTab? {
#if DEBUG
        let value = ProcessInfo.processInfo.environment["PRISMESH_INITIAL_TAB"]?.lowercased()
        switch value {
        case "home": return .home
        case "alerts": return .alerts
        case "activity": return .activity
        case "feedback": return .feedback
        default: return nil
        }
#else
        return nil
#endif
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

enum WalletConnectStatus: Equatable {
    case connecting
    case success
    case failure
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

    private var displayTitle: String {
        let name = event.metadata.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.caseInsensitiveCompare("Unknown Token") == .orderedSame || name.isEmpty {
            return "Unknown Token • …\(event.mint.suffix(4))"
        }
        return name
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(severity.color.opacity(0.78))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 5) {
                Text(severity.rawValue.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(severity.color.opacity(0.2))
                    .foregroundStyle(severity.color)
                    .clipShape(Capsule())

                HStack(spacing: 8) {
                    TokenIconView(
                        symbol: event.metadata.symbol,
                        mint: event.mint,
                        logoURL: event.metadata.logoURL,
                        size: 34
                    )
                    Text(displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(RadarTheme.Palette.textPrimary)
                        .lineLimit(1)
                }

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

private struct TabItemView: View {
    let tab: BetaTab
    let selected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: tab.icon)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text(tab.rawValue)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(
            selected
            ? DesignSystem.Colors.accent.opacity(0.95)
            : DesignSystem.Colors.textMuted
        )
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .contentShape(Rectangle())
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DesignSystem.Colors.accent.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.05), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
            }
        }
        .scaleEffect(selected ? 1.02 : 1.0)
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: selected)
    }
}

private struct WalletRowStatus {
    let message: String
    let icon: String
    let color: Color
    let showsProgress: Bool
}

private struct ConnectWalletButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct StatTripletRow: View {
    struct Metric: Identifiable {
        let label: String
        let valueText: String

        var id: String { label }
    }

    let metrics: [Metric]

    private let columns = [
        GridItem(.flexible(), spacing: DesignSystem.Spacing.md),
        GridItem(.flexible(), spacing: DesignSystem.Spacing.md),
        GridItem(.flexible(), spacing: DesignSystem.Spacing.md)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    Text(metric.valueText)
                        .font(DesignSystem.Typography.metricMedium)
                        .monospacedDigit()
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.95)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(metric.label)
                        .font(DesignSystem.Typography.meta)
                        .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.92))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct MonitoringDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 8, height: 8)
            .scaleEffect(isPulsing ? 1.2 : 0.8)
            .onAppear { isPulsing = true }
            .animation(
                .easeInOut(duration: 1).repeatForever(),
                value: isPulsing
            )
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
