import SwiftUI
import PhotosUI
import UIKit

private enum BetaTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case intelligence = "Intelligence"
    case alerts = "Alerts"
    case profile = "Profile"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "house"
        case .intelligence: return "chart.xyaxis.line"
        case .alerts: return "bell.badge"
        case .profile: return "person"
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

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum BreakdownSegment: String, CaseIterable {
    case tokens = "Tokens"
    case contracts = "Contracts"
    case nfts = "NFTs"
}

struct ContentView: View {
    @StateObject private var viewModel: DashboardViewModel
    @FocusState private var walletFieldFocused: Bool
    @State private var selectedTab: BetaTab = .dashboard
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
    @State private var isConnectingWallet = false
    @State private var didJustConnect = false
    @State private var walletConnectStatus: WalletConnectStatus?
    @State private var connectButtonPulse = false
    @State private var showJustUpdatedStatus = false
    @State private var didApplyLaunchTab = false
    @State private var isRetryingScanStatus = false
    @State private var scrollY: CGFloat = 0
    @State private var selectedBreakdownSegment: BreakdownSegment = .tokens
    @State private var didRunInitialLoad = false
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
                    case .dashboard:
                        homeView
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                )
                            )

                    case .intelligence:
                        intelligenceView
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

                    case .profile:
                        profileView
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
                ThemeTokens.Background.base
                    .ignoresSafeArea()
                LinearGradient(
                    colors: [
                        ThemeTokens.Background.top.opacity(0.58),
                        ThemeTokens.Background.base.opacity(0.42),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .init(x: 0.5, y: 0.56)
                )
                .ignoresSafeArea()
                RadialGradient(
                    colors: [
                        ThemeTokens.Accent.green.opacity(0.07),
                        Color.clear
                    ],
                    center: .init(x: 0.5, y: 0.28),
                    startRadius: 20,
                    endRadius: 420
                )
                .ignoresSafeArea()
                LinearGradient(
                    colors: [
                        Color.clear,
                        ThemeTokens.Background.vignette
                    ],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                IntelligenceBackgroundLayer(sweepRotation: radarSweepRotation)
                    .ignoresSafeArea()
            }
        }
        .task {
            guard !didRunInitialLoad else { return }
            didRunInitialLoad = true
            await viewModel.onAppear()
            guard viewModel.hasValidWalletAddress, !viewModel.isMaintenanceMode else { return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            _ = await viewModel.startScan(reason: "post_paint")
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
                selectedTab = .profile
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
        .onPreferenceChange(ScrollOffsetKey.self) { value in
            // Throttle offset updates to avoid full-screen re-renders on every scroll pixel.
            let clamped = max(-180, min(60, value))
            guard abs(clamped - scrollY) >= 2 else { return }
            scrollY = clamped
        }
    }

    private var header: some View {
        let effectiveScrollY = selectedTab == .dashboard ? scrollY : 0
        let t = min(1, max(0, (-effectiveScrollY) / 120))
        let materialOpacity = 0.40 + (0.28 * t)
        let overlayDark = 0.20 + (0.24 * t)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xs) {
                Text("Wallet Yield & Risk Intelligence")
                    .font(.system(size: 21, weight: .semibold, design: .default))
                    .tracking(0.25)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.74)
                    .foregroundStyle(Color.white.opacity(0.98))
                Spacer()
                MonitoringDot(size: 6)
            }

            Text("Monitoring")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.66))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .background {
            ZStack {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ThemeTokens.Card.top.opacity(0.92 + (0.06 * t)),
                                ThemeTokens.Card.bottom.opacity(0.95 + (0.04 * t))
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Rectangle().fill(Color.black.opacity(overlayDark + 0.06))
                LinearGradient(
                    colors: [ThemeTokens.Card.innerHighlight.opacity(materialOpacity), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        }
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1),
            alignment: .top
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
        .onLongPressGesture(minimumDuration: 0.7) {
            guard diagnosticsEnabled else { return }
            showAbout = true
        }
    }

    private var walletControlCard: some View {
        DarkCard(cornerRadius: 24, contentPadding: 16) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Wallet")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                WalletInputView(
                    walletAddress: $viewModel.walletAddress,
                    isFocused: $walletFieldFocused,
                    walletConnectStatus: nil,
                    walletErrorMessage: viewModel.walletValidationMessage
                )

                HStack(spacing: DesignSystem.Spacing.sm) {
                    Button {
                        Task { await connectAndSyncIfNeeded() }
                    } label: {
                        HStack(spacing: 6) {
                            if isConnectingWallet {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(ThemeTokens.Background.base.opacity(0.95))
                            }
                            Text(isConnectingWallet ? "Connecting..." : (viewModel.isConnected ? "Update" : "Connect"))
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ThemeTokens.Background.base.opacity(0.95))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DesignSystem.Colors.accent)
                    )
                    .disabled(!viewModel.isWalletAddressValid || isConnectingWallet)
                    .opacity((!viewModel.isWalletAddressValid || isConnectingWallet) ? 0.55 : 1.0)
                    .buttonStyle(ConnectWalletButtonStyle())

                    Button("Refresh") {
                        Haptic.medium()
                        Task { await performRefresh() }
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(DesignSystem.Colors.surfaceElevated)
                    .overlay(Capsule().stroke(DesignSystem.Colors.border, lineWidth: 1))
                    .clipShape(Capsule())
                    .disabled(
                        !viewModel.isWalletAddressValid ||
                        viewModel.isRefreshing ||
                        isConnectingWallet ||
                        viewModel.isLoading
                    )
                    .opacity((!viewModel.isWalletAddressValid || viewModel.isRefreshing) ? 0.55 : 1.0)

                    Spacer()
                }

                walletControlStatusLine
            }
        }
    }

    private var walletControlStatusLine: some View {
        HStack(spacing: 8) {
            if !viewModel.hasWalletAddress {
                Image(systemName: "info.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text("Paste a Solana wallet address to begin.")
                    .font(DesignSystem.Typography.meta.weight(.medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            } else if !viewModel.isWalletAddressValid {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.warning)
                Text(viewModel.walletValidationMessage ?? "Enter a valid wallet address.")
                    .font(DesignSystem.Typography.meta.weight(.medium))
                    .foregroundStyle(DesignSystem.Colors.warning)
            } else if scanStatusState.retryable {
                Button {
                    guard !isRetryingScanStatus else { return }
                    Haptic.medium()
                    isRetryingScanStatus = true
                    Task {
                        await performRefresh()
                        await MainActor.run { isRetryingScanStatus = false }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                        Text(isRetryingScanStatus ? "Retrying..." : "Scan failed. Tap retry.")
                            .font(DesignSystem.Typography.meta.weight(.semibold))
                    }
                    .foregroundStyle(DesignSystem.Colors.danger)
                }
                .buttonStyle(.plain)
            } else if scanStatusState.showsLoading || isConnectingWallet {
                ProgressView()
                    .controlSize(.mini)
                    .tint(DesignSystem.Colors.textSecondary)
                Text("Scanning...")
                    .font(DesignSystem.Typography.meta.weight(.medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            } else {
                Image(systemName: "checkmark.seal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.safe)
                Text("Connected (\(shortWalletAddress(viewModel.walletAddress)))")
                    .font(DesignSystem.Typography.meta.weight(.medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            Spacer()
        }
    }

    private func shortWalletAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10 else { return trimmed }
        return "\(trimmed.prefix(4))...\(trimmed.suffix(4))"
    }

    private var scanStatusRow: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.xs) {
                Text("Scan status")
                    .font(DesignSystem.Typography.meta.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Spacer()

                if scanStatusState.retryable {
                    Button {
                        guard !isRetryingScanStatus else { return }
                        Haptic.medium()
                        isRetryingScanStatus = true
                        Task {
                            await performRefresh()
                            await MainActor.run {
                                isRetryingScanStatus = false
                            }
                        }
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            if isRetryingScanStatus {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(scanStatusState.color)
                                Text("Retrying...")
                                    .font(DesignSystem.Typography.meta.weight(.semibold))
                            } else {
                                Image(systemName: scanStatusState.icon)
                                    .font(.system(size: 11, weight: .bold))
                                Text("Scan failed. Tap to retry.")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                        }
                        .foregroundStyle(scanStatusState.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            Capsule(style: .continuous)
                                .fill(ThemeTokens.Accent.criticalMutedBackground)
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(scanStatusState.color.opacity(0.38), lineWidth: 1)
                        )
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRetryingScanStatus)
                } else {
                    if scanStatusState.showsLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(DesignSystem.Colors.textSecondary)
                    } else {
                        Image(systemName: scanStatusState.icon)
                            .font(.caption.weight(.semibold))
                    }
                    Text(scanStatusState.message)
                        .font(DesignSystem.Typography.meta.weight(.medium))
                        .foregroundStyle(scanStatusState.color)
                }
            }

            if scanStatusState.showsLoading {
                ScanStatusLoadingLine()
                    .transition(.opacity)
            }
            if scanStatusState.retryable, let scanErrorCodeText {
                Text(scanErrorCodeText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.top, 2)
        .animation(.easeInOut(duration: 0.2), value: scanStatusState.message)
    }

    private var scanStatusState: ScanStatusState {
#if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["PRISMESH_FORCE_SCAN_LOADING"] == "1" {
            return ScanStatusState(message: "Scanning wallet activity...", icon: "waveform.path.ecg", color: DesignSystem.Colors.textSecondary, showsLoading: true, retryable: false, isError: false)
        }
        if env["PRISMESH_FORCE_SCAN_ERROR"] == "1" {
            return ScanStatusState(message: "Scan failed. Tap to retry.", icon: "exclamationmark.triangle.fill", color: DesignSystem.Colors.danger, showsLoading: false, retryable: true, isError: true)
        }
#endif

        switch viewModel.scanStatus {
        case .failure:
            if viewModel.showActionableScanFailure {
                return ScanStatusState(
                    message: "Scan failed. Tap to retry.",
                    icon: "exclamationmark.triangle.fill",
                    color: DesignSystem.Colors.danger,
                    showsLoading: false,
                    retryable: true,
                    isError: true
                )
            }
            return ScanStatusState(
                message: viewModel.passiveScanFailureMessage ?? "Monitoring warming up",
                icon: "clock.badge.exclamationmark",
                color: DesignSystem.Colors.textSecondary,
                showsLoading: false,
                retryable: false,
                isError: false
            )
        case .scanning:
            if isConnectingWallet {
                return ScanStatusState(message: "Connecting...", icon: "link", color: DesignSystem.Colors.textSecondary, showsLoading: true, retryable: false, isError: false)
            }
            return ScanStatusState(message: "Scanning wallet activity...", icon: "waveform.path.ecg", color: DesignSystem.Colors.textSecondary, showsLoading: true, retryable: false, isError: false)
        case .success(let checked):
            let age = Date().timeIntervalSince(checked)
            if age > 6 * 60 * 60 {
                return ScanStatusState(message: "Delayed sync", icon: "clock.badge.exclamationmark", color: DesignSystem.Colors.warning, showsLoading: false, retryable: true, isError: false)
            }
            return ScanStatusState(message: "Updated \(relativeFormatter.localizedString(for: checked, relativeTo: Date()))", icon: "clock", color: DesignSystem.Colors.textSecondary, showsLoading: false, retryable: false, isError: false)
        case .idle:
            return ScanStatusState(message: "Ready", icon: "checkmark.seal", color: DesignSystem.Colors.textSecondary, showsLoading: false, retryable: false, isError: false)
        }
    }

    private var relativeFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }

    private var scanErrorCodeText: String? {
        guard case let .failure(message) = viewModel.scanStatus else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let code = trimmed.replacingOccurrences(of: "\n", with: " ").prefix(48)
        return "Code: \(code)"
    }

    private func markScanUpdated() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showJustUpdatedStatus = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showJustUpdatedStatus = false
                }
            }
        }
    }

    private struct ScanStatusState {
        let message: String
        let icon: String
        let color: Color
        let showsLoading: Bool
        let retryable: Bool
        let isError: Bool
    }

    private struct ScanStatusLoadingLine: View {
        @State private var phase: CGFloat = -1

        var body: some View {
            Capsule()
                .fill(Color.white.opacity(0.08))
                .frame(height: 2)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, DesignSystem.Colors.accent.opacity(0.45), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 72, height: 2)
                        .offset(x: phase * 220)
                }
                .clipped()
                .onAppear {
                    phase = -1
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
        }
    }

    private var homeView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.xl) {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self, value: geo.frame(in: .named("scroll")).minY)
                }
                .frame(height: 0)

                walletControlCard
                    .animation(.easeInOut(duration: 0.2), value: scanStatusState.message)

                if !viewModel.isWalletAddressValid {
                    emptyStateCard
                } else if viewModel.isLoading && viewModel.historyEvents.isEmpty {
                    dashboardSkeletonState
                } else {
                    intelligenceSummaryCard

                    threatSurfaceBreakdownCard

                    behavioralPatternAnalysisCard

                    protectionStatusCard

                    if viewModel.nftCountLoadState == .success && !viewModel.nftItems.isEmpty {
                        nftGallerySection
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

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
            .opacity(viewModel.isRefreshing ? 0.6 : 1)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isRefreshing)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.bottom, DesignSystem.Spacing.xl)
            .padding(.top, 4)
        }
        .refreshable {
            viewModel.trackPullToRefresh()
            await performRefresh()
        }
        .coordinateSpace(name: "scroll")
    }

    private var intelligenceSummaryCard: some View {
        DarkCard(cornerRadius: 26, contentPadding: 20) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack {
                    Text("Exposure Index")
                        .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Spacer()
                    HStack(spacing: 6) {
                        MonitoringDot(size: 7)
                        Text("Live")
                            .font(DesignSystem.Typography.meta.weight(.semibold))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                    }
                }

                HStack(alignment: .lastTextBaseline, spacing: DesignSystem.Spacing.xs) {
                    Text(exposureIndexDisplay)
                        .font(DesignSystem.Typography.metricLarge)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: exposureIndex)
                    Text("Exposure Index")
                        .font(DesignSystem.Typography.body.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    MetricPill(level: exposureThreatLevel)
                }

                TrendChip(value: exposureTrendValue, suffix: "24h")

                RiskScoreProgressBar(progress: Double(exposureIndex) / 100.0)

                Text(exposureReasonText)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.96))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Last scan: \(lastScanRelativeText)")
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
        }
    }

    private var threatSurfaceBreakdownCard: some View {
        DarkCard(cornerRadius: 26, contentPadding: 18) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                HStack {
                    Text("Threat Surface")
                        .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Spacer()
                    Text("Engineered")
                        .font(DesignSystem.Typography.meta.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.accent)
                }

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(threatSurfaceMetrics, id: \.label) { metric in
                        MiniMetricCard(
                            title: metric.label,
                            value: "\(metric.score)",
                            trendText: metric.trend,
                            severityColor: metric.severityColor
                        )
                    }
                }
            }
        }
    }

    private var behavioralPatternAnalysisCard: some View {
        DarkCard(cornerRadius: 26, contentPadding: 18) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("Behavioral Pattern Analysis")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 0.75)

                ForEach(behavioralMetrics, id: \.label) { metric in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metric.label)
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            Text(metric.value)
                                .font(DesignSystem.Typography.body.weight(.semibold))
                                .foregroundStyle(DesignSystem.Colors.textPrimary)
                        }
                        Spacer()
                        SparklineView(values: metric.sparkline)
                            .frame(width: 72, height: 24)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var protectionStatusCard: some View {
        DarkCard(cornerRadius: 26, contentPadding: 18) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("Protection Coverage")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                protectionStatusRow(
                    title: "Monitoring",
                    value: viewModel.autoScanEnabled ? "ON" : "MANUAL",
                    isOn: true
                )
                protectionStatusRow(
                    title: "High-risk contracts",
                    value: "Enabled",
                    isOn: true
                )
                protectionStatusRow(
                    title: "Anomaly detection",
                    value: hasLastUpdated ? "Enabled" : "Coming soon",
                    isOn: hasLastUpdated
                )
                protectionStatusRow(
                    title: "Alert channels",
                    value: viewModel.notificationsEnabled ? "Push" : "Configured: —",
                    isOn: viewModel.notificationsEnabled
                )
            }
        }
    }

    private func protectionStatusRow(title: String, value: String, isOn: Bool) -> some View {
        HStack {
            Image(systemName: isOn ? "checkmark.shield.fill" : "shield")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? DesignSystem.Colors.safe : DesignSystem.Colors.textSecondary)
            Text(title)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.meta.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }

    private struct ThreatSurfaceMetric {
        let label: String
        let score: Int
        let trend: String

        var severityColor: Color {
            if score >= 75 { return DesignSystem.Colors.danger }
            if score >= 45 { return DesignSystem.Colors.warning }
            return DesignSystem.Colors.safe
        }
    }

    private struct BehavioralMetricData {
        let label: String
        let value: String
        let sparkline: [Double]
    }

    private var nftGallerySection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text("NFT Collection")
                    .font(DesignSystem.Typography.cardTitle)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Spacer()
                Text("\(viewModel.nftCount) total")
                    .font(DesignSystem.Typography.meta.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textMuted)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(viewModel.nftItems.prefix(12)) { item in
                        NFTThumbnailCell(item: item)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var breakdownPillsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text("Breakdown")
                .font(DesignSystem.Typography.cardTitle)
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    breakdownPill(title: "Tokens", count: tokensCount, segment: .tokens)
                    breakdownPill(title: "Contracts", count: contractsCount, segment: .contracts)
                    breakdownPill(
                        title: "NFTs",
                        countText: nftPillCountText,
                        segment: .nfts,
                        badgeSystemImage: viewModel.nftCountLoadState == .failure ? "exclamationmark.triangle.fill" : nil,
                        showsSpinner: viewModel.nftCountLoadState == .loading
                    )
                        .onTapGesture {
                            guard viewModel.nftCountLoadState == .failure else { return }
                            Haptic.medium()
                            Task { await retryNFTLoad() }
                        }
                }
                .padding(.vertical, 2)
            }

            if viewModel.nftCountLoadState == .failure {
                inlineRetryRow(message: "Couldn’t load NFTs. Tap to retry.", tintColor: DesignSystem.Colors.warning) {
                    Haptic.medium()
                    Task { await retryNFTLoad() }
                }
            }

            if diagnosticsEnabled, let nftDiagnosticsSummary = viewModel.nftDiagnosticsSummary {
                Text(nftDiagnosticsSummary)
                    .font(DesignSystem.Typography.meta)
                    .foregroundStyle(DesignSystem.Colors.textMuted)
            }
        }
    }

    private func breakdownPill(title: String, count: Int, segment: BreakdownSegment) -> some View {
        breakdownPill(title: title, countText: "\(count)", segment: segment)
    }

    private func breakdownPill(
        title: String,
        countText: String,
        segment: BreakdownSegment,
        badgeSystemImage: String? = nil,
        showsSpinner: Bool = false
    ) -> some View {
        let isSelected = selectedBreakdownSegment == segment
        return HStack(spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(isSelected ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary.opacity(0.92))
            Text("(\(countText))")
                .font(DesignSystem.Typography.body.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            if showsSpinner {
                ProgressView()
                    .controlSize(.mini)
                    .tint(DesignSystem.Colors.textMuted)
            } else if let badgeSystemImage {
                Image(systemName: badgeSystemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.warning)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background {
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            ThemeTokens.Card.top.opacity(isSelected ? 0.98 : 0.95),
                            ThemeTokens.Card.bottom.opacity(isSelected ? 0.98 : 0.95)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(DesignSystem.Colors.accent.opacity(0.13))
                    }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .fill(LinearGradient(
                            colors: [ThemeTokens.Card.innerHighlight.opacity(isSelected ? 1.0 : 0.82), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                }
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(isSelected ? 0.24 : 0.16), Color.white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        }
        .clipShape(Capsule(style: .continuous))
        .onTapGesture {
            selectedBreakdownSegment = segment
        }
    }

    private func inlineRetryRow(message: String, tintColor: Color, onRetry: @escaping () -> Void) -> some View {
        Button(action: onRetry) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(message)
                    .font(DesignSystem.Typography.meta.weight(.medium))
                Spacer()
                Text("Retry")
                    .font(DesignSystem.Typography.meta.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(tintColor.opacity(0.18))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(tintColor.opacity(0.40), lineWidth: 0.75)
                            )
                    )
            }
            .foregroundStyle(tintColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tintColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(tintColor.opacity(0.22), lineWidth: 0.75)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var walletPatternAnalysisPanel: some View {
        DarkCard(cornerRadius: 26, contentPadding: 18) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                Text("Wallet Pattern Analysis")
                    .font(DesignSystem.Typography.cardTitle.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 0.75)

                patternAnalysisRow(label: "Most interacted protocol", value: mostInteractedProtocol, trend: nil)
                patternAnalysisRow(label: "Interaction frequency", value: interactionFrequencyTrend, trend: .up)
                patternAnalysisRow(label: "Avg holding time", value: averageHoldingTime, trend: nil)
                patternAnalysisRow(label: "Risk delta 7D", value: riskDelta7D, trend: riskDelta7DTrendDirection)
            }
        }
    }

    private enum TrendDirection { case up, down }

    private var riskDelta7DTrendDirection: TrendDirection {
        let delta = (viewModel.highRiskCount * 3) - 4
        return delta >= 0 ? .up : .down
    }

    private func patternAnalysisRow(label: String, value: String, trend: TrendDirection?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(Color.white.opacity(0.76))
            Spacer()
            HStack(spacing: 4) {
                if let trend {
                    Image(systemName: trend == .up ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(
                            trend == .up
                                ? Color(red: 0.25, green: 0.80, blue: 0.45)
                                : Color(red: 0.90, green: 0.35, blue: 0.35)
                        )
                }
                Text(value)
                    .font(DesignSystem.Typography.body.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 2)
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
        .intelligenceCardStyle(cornerRadius: DesignSystem.Radius.lg)
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
                    intelligenceFeedRow(
                        text: "New contract interaction detected",
                        color: DesignSystem.Colors.accent,
                        icon: "dot.radiowaves.left.and.right"
                    )
                    intelligenceFeedRow(
                        text: "Risk delta \(exposureTrendText.replacingOccurrences(of: "↑ ", with: "").replacingOccurrences(of: "↓ ", with: ""))",
                        color: exposureTrendValue >= 0 ? DesignSystem.Colors.warning : DesignSystem.Colors.safe,
                        icon: exposureTrendValue >= 0 ? "arrow.up.right" : "arrow.down.right"
                    )
                    intelligenceFeedRow(
                        text: "Liquidity exposure increased",
                        color: DesignSystem.Colors.warning,
                        icon: "drop.triangle"
                    )
                    intelligenceFeedRow(
                        text: "Protocol trust rating \(protocolTrustMessage)",
                        color: protocolTrustMessage == "downgraded" ? DesignSystem.Colors.danger : DesignSystem.Colors.safe,
                        icon: "shield.lefthalf.filled"
                    )
                }
            }
        }
    }

    private func intelligenceFeedRow(text: String, color: Color, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(DesignSystem.Typography.body.weight(.semibold))
            .foregroundStyle(color)
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
        .padding(16)
        .cardStyleLeft(cornerRadius: DesignSystem.Radius.lg)
    }

    private var reminderBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick check-in: anything confusing or missing?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            HStack(spacing: 10) {
                Button("Send Feedback") {
                    viewModel.reminderFeedbackTapped()
                    viewModel.trackFeedbackOpen()
                    selectedTab = .profile
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.black.opacity(0.9))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DesignSystem.Colors.accent)
                .clipShape(Capsule())

                Button("Dismiss") {
                    viewModel.dismissReminderBanner()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DesignSystem.Colors.surface, in: Capsule(style: .continuous))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75))

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardStyleLeft(cornerRadius: DesignSystem.Radius.lg)
    }

    private var alertsView: some View {
        let filteredAlerts = filteredAlertEvents
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("Alerts")
                    .font(DesignSystem.Typography.h2.weight(.bold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

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

    private var intelligenceView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text("Intelligence")
                    .font(DesignSystem.Typography.h2.weight(.bold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

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
                                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                                    Text("Est. \(estimatedUSDText(for: event))")
                                        .font(.caption2)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.72))
                                    Text(event.detectedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.88))
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .cardStyleLeft(cornerRadius: DesignSystem.Radius.lg)
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

    private var profileView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Profile")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text("Tell us what blocked you. Keep it short.")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                TextEditor(text: $feedbackMessage)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160)
                    .padding(8)
                    .background(DesignSystem.Colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(DesignSystem.Colors.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                PhotosPicker(selection: $selectedScreenshot, matching: .images) {
                    Text(screenshotBase64 == nil ? "Attach Screenshot (optional)" : "Screenshot attached")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(DesignSystem.Colors.surface)
                        .overlay(Capsule().stroke(DesignSystem.Colors.border, lineWidth: 1))
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
                .background(DesignSystem.Colors.accent)
                .clipShape(Capsule())
                .disabled(isSendingFeedback || feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let feedbackStatus {
                    Text(feedbackStatus)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }

                if diagnosticsEnabled {
                    Button("About / Diagnostics") {
                        showAbout = true
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(DesignSystem.Colors.surface)
                    .overlay(Capsule().stroke(DesignSystem.Colors.border, lineWidth: 1))
                    .clipShape(Capsule())
                }

                Text("Build ID: \(buildID)")
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
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
            .foregroundStyle(DesignSystem.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .cardStyleLeft(cornerRadius: DesignSystem.Radius.lg)
    }

    private var tabBar: some View {
        BottomDock(
            items: BetaTab.allCases.map {
                BottomDockItem(id: $0.rawValue, title: $0.rawValue, systemImage: $0.icon)
            },
            selectedID: Binding(
                get: { selectedTab.rawValue },
                set: { newValue in
                    guard let tab = BetaTab(rawValue: newValue) else { return }
                    selectedTab = tab
                }
            )
        ) { selectedID in
            guard let tab = BetaTab(rawValue: selectedID), selectedTab != tab else { return }
            Haptic.light()
            selectedTab = tab
            if tab == .alerts { viewModel.trackAlertsTabOpen() }
            if tab == .intelligence { viewModel.trackActivityTabOpen() }
            if tab == .profile { viewModel.trackFeedbackOpen() }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func connectAndSyncIfNeeded() async {
        guard !isConnectingWallet else { return }
        guard viewModel.isWalletAddressValid else {
            Haptic.warning()
            walletConnectStatus = .failure
            return
        }
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
        let previousLast = viewModel.lastCheckedAt
        firstSyncInProgress = true
        _ = await viewModel.startScan(reason: "retry")
        firstSyncInProgress = false
        if case .success = viewModel.scanStatus, viewModel.lastCheckedAt != nil, viewModel.lastCheckedAt != previousLast {
            Haptic.success()
            markScanUpdated()
        } else if case .failure = viewModel.scanStatus {
            Haptic.warning()
            withAnimation(.easeInOut(duration: 0.2)) {
                walletConnectStatus = .failure
            }
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

    @MainActor
    private func performRefresh() async {
        guard !viewModel.isRefreshing else { return }
        guard viewModel.isWalletAddressValid else {
            Haptic.warning()
            return
        }
#if DEBUG
        print("[ScanDebug] manual refresh requested")
#endif
        let previousLast = viewModel.lastCheckedAt
        _ = await viewModel.startScan(reason: "pull_to_refresh")
        if case .success = viewModel.scanStatus, viewModel.lastCheckedAt != nil, viewModel.lastCheckedAt != previousLast {
            Haptic.success()
            markScanUpdated()
        } else if case .failure = viewModel.scanStatus {
            Haptic.warning()
        }
    }

    @MainActor
    private func retryNFTLoad() async {
        await viewModel.refreshNFTCountsOnly()
        switch viewModel.nftCountLoadState {
        case .success:
            Haptic.success()
        case .failure:
            Haptic.warning()
        default:
            break
        }
    }

    private var confidenceColor: Color {
        switch viewModel.dataConfidenceLabel {
        case "High confidence data": return DesignSystem.Colors.accent.opacity(0.78)
        case "Partial data": return DesignSystem.Colors.warning
        default: return DesignSystem.Colors.danger
        }
    }

    private func walletStatusColor(_ status: WalletConnectStatus) -> Color {
        switch status {
        case .connecting: return DesignSystem.Colors.textSecondary
        case .success:    return Color(red: 0.25, green: 0.80, blue: 0.45)
        case .failure:    return DesignSystem.Colors.danger
        }
    }

    private func walletStatusLabel(_ status: WalletConnectStatus) -> String {
        switch status {
        case .connecting: return "Connecting…"
        case .success:    return "Connected — syncing"
        case .failure:    return "Connection failed"
        }
    }

    private var connectWalletButtonColor: Color {
        DesignSystem.Colors.accent.opacity(0.88)
    }

    @ViewBuilder
    private var connectWalletButtonLabel: some View {
        HStack(spacing: 6) {
            if isConnectingWallet {
                ProgressView()
                    .tint(Color.black.opacity(0.84))
                    .scaleEffect(0.85)
            } else if didJustConnect || walletConnectStatus == .success {
                Image(systemName: "checkmark.circle.fill")
            }

            Text(
                isConnectingWallet
                ? "Connecting…"
                : ((didJustConnect || walletConnectStatus == .success) ? "Connected" : "Connect Wallet")
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

    // Exposure Index (professional framing):
    // Contract Risk (30%) + Protocol Trust inverse (20%) + Interaction Velocity (15%)
    // + Asset Volatility proxy (15%) + Counterparty Risk (20%)
    private var exposureIndex: Int {
        guard viewModel.hasValidWalletAddress else { return 0 }
        let contractRisk = min(100, viewModel.highRiskCount * 18 + viewModel.mediumRiskCount * 8)
        let protocolTrustInverse = max(0, 100 - integrityScore)
        let interactionVelocity = min(100, viewModel.historyEvents.count * 10)
        let assetVolatilityProxy = min(100, Int((NSDecimalNumber(decimal: viewModel.totalDetectedAmount).doubleValue * 6).rounded()))
        let counterpartyRisk = min(100, unverifiedAssetsCount * 16 + suspiciousTokensCount * 12)

        let weighted =
            (Double(contractRisk) * 0.30) +
            (Double(protocolTrustInverse) * 0.20) +
            (Double(interactionVelocity) * 0.15) +
            (Double(assetVolatilityProxy) * 0.15) +
            (Double(counterpartyRisk) * 0.20)

        return max(0, min(100, Int(weighted.rounded())))
    }

    private var uptimePercentage: Int {
        guard viewModel.hasValidWalletAddress else { return 0 }
        switch viewModel.scanStatus {
        case .success(let checkedAt):
            let hours = Date().timeIntervalSince(checkedAt) / 3600
            if hours <= 1 { return 99 }
            if hours <= 6 { return 97 }
            if hours <= 24 { return 94 }
            return 90
        case .scanning:
            return 96
        case .failure:
            return 82
        case .idle:
            return hasLastUpdated ? 93 : 88
        }
    }

    private var contributionScore: Int {
        guard viewModel.hasValidWalletAddress else { return 0 }
        let activityComponent = min(30, viewModel.historyEvents.count * 2)
        let trustComponent = max(0, min(30, integrityScore / 3))
        let uptimeComponent = max(0, min(40, Int((Double(uptimePercentage) * 0.4).rounded())))
        return max(0, min(100, activityComponent + trustComponent + uptimeComponent))
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

    private var nodeStatusLabel: String {
        viewModel.hasValidWalletAddress && !scanStatusState.isError ? "Online" : "Offline"
    }

    private var nodeStatusColor: Color {
        nodeStatusLabel == "Online" ? DesignSystem.Colors.safe : DesignSystem.Colors.danger
    }

    private var uptimePercentageText: String {
        "\(uptimePercentage)%"
    }

    private var rewardsTodayText: String {
        guard hasLastUpdated else { return "—" }
        let amount = max(0, NSDecimalNumber(decimal: viewModel.latestDetectedAmount).doubleValue)
        if amount == 0 {
            return "0.00"
        }
        return String(format: "%.2f", amount)
    }

    private var networkClusterLabel: String {
        AppEnvironment.current.environmentName.lowercased() == "production" ? "Solana Mainnet" : "Solana \(AppEnvironment.current.environmentName.capitalized)"
    }

    private var networkClusterShort: String {
        AppEnvironment.current.environmentName.lowercased() == "production" ? "Mainnet" : AppEnvironment.current.environmentName.capitalized
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
        case .idle:
            return "—"
        case .loading:
            return "..."
        case .success:
            return "\(viewModel.totalNFTCount)"
        case .failure:
            return "—"
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
            return "Moderate (+8%)"
        default:
            return "High (+16%)"
        }
    }

    private var averageHoldingTime: String {
        let events = viewModel.historyEvents
        guard !events.isEmpty else { return "—" }

        let now = Date()
        let totalAgeSeconds = events.reduce(0.0) { partial, event in
            partial + max(0, now.timeIntervalSince(event.detectedAt))
        }
        let averageAgeSeconds = totalAgeSeconds / Double(events.count)
        return formattedHoldingTime(seconds: averageAgeSeconds)
    }

    private func formattedHoldingTime(seconds: TimeInterval) -> String {
        let minute: TimeInterval = 60
        let hour: TimeInterval = 60 * minute
        let day: TimeInterval = 24 * hour

        if seconds >= day {
            let days = seconds / day
            return String(format: "%.1f days (est.)", days)
        }
        if seconds >= hour {
            let hours = Int((seconds / hour).rounded())
            return "\(hours)h (est.)"
        }
        if seconds >= minute {
            let minutes = Int((seconds / minute).rounded())
            return "\(minutes)m (est.)"
        }
        return "<1m (est.)"
    }

    private var riskDelta7D: String {
        guard hasLastUpdated else { return "—" }
        return "-1%"
    }

    private var highRiskContract48hCount: Int {
        let cutoff = Date().addingTimeInterval(-48 * 60 * 60)
        return viewModel.historyEvents.filter { $0.detectedAt >= cutoff && $0.risk.score >= 70 }.count
    }

    private var exposureStatusLabel: String {
        switch exposureIndex {
        case ..<25: return "Low"
        case ..<50: return "Guarded"
        case ..<75: return "Elevated"
        default: return "Critical"
        }
    }

    private var exposureThreatLevel: ThreatLevel {
        switch exposureStatusLabel {
        case "Low": return .low
        case "Guarded": return .guarded
        case "Elevated": return .elevated
        default: return .critical
        }
    }

    private var exposureStatusColor: Color {
        switch exposureStatusLabel {
        case "Low": return DesignSystem.Colors.safe
        case "Guarded": return Color(red: 0.80, green: 0.88, blue: 1.0)
        case "Elevated": return DesignSystem.Colors.warning
        default: return DesignSystem.Colors.danger
        }
    }

    private var exposureTrendValue: Double {
        let base = Double(viewModel.highRiskCount * 2) + (Double(viewModel.mediumRiskCount) * 0.9) - 1.2
        return max(-9.9, min(9.9, base))
    }

    private var exposureTrendText: String {
        String(format: "%@%.1f%% (24h)", exposureTrendValue >= 0 ? "↑ +" : "↓ ", abs(exposureTrendValue))
    }

    private var exposureReasonText: String {
        "Your exposure increased due to \(highRiskContract48hCount) high-risk contract interaction\(highRiskContract48hCount == 1 ? "" : "s") in the last 48h."
    }

    private var threatSurfaceMetrics: [ThreatSurfaceMetric] {
        [
            .init(label: "Contract Risk Exposure", score: min(100, viewModel.highRiskCount * 20 + viewModel.mediumRiskCount * 10), trend: "+\(max(1, viewModel.highRiskCount))%"),
            .init(label: "Protocol Trust Risk", score: min(100, max(0, 100 - integrityScore)), trend: "+\(min(15, max(2, viewModel.mediumRiskCount * 2)))%"),
            .init(label: "Counterparty Risk", score: min(100, unverifiedAssetsCount * 15 + suspiciousTokensCount * 10), trend: "+\(max(2, unverifiedAssetsCount * 2))%"),
            .init(label: "Interaction Velocity", score: min(100, viewModel.historyEvents.count * 9), trend: "+\(min(22, max(3, viewModel.historyEvents.count * 2)))%")
        ]
    }

    private var liquidityRiskTrendText: String {
        let pct = min(18, max(2, viewModel.mediumRiskCount * 3))
        return "+\(pct)%"
    }

    private var protocolTrustMessage: String {
        exposureIndex >= 55 ? "downgraded" : "stable"
    }

    private var behavioralMetrics: [BehavioralMetricData] {
        [
            .init(label: "Interaction Velocity (vs baseline)", value: "\(min(190, 86 + viewModel.historyEvents.count * 8))%", sparkline: [0.38, 0.41, 0.45, 0.50, 0.56, 0.63, 0.69]),
            .init(label: "Contract Novelty Score", value: "\(min(100, 34 + unverifiedAssetsCount * 9))", sparkline: [0.30, 0.32, 0.34, 0.37, 0.41, 0.46, 0.49]),
            .init(label: "Unusual Flow Detection", value: exposureStatusLabel, sparkline: [0.35, 0.36, 0.38, 0.43, 0.40, 0.47, 0.52]),
            .init(label: "Risk Acceleration", value: exposureTrendText, sparkline: [0.28, 0.33, 0.36, 0.44, 0.57, 0.64, 0.71])
        ]
    }

    private var lastScanRelativeText: String {
        guard let lastCheckedAt = viewModel.lastCheckedAt else { return "—" }
        return relativeFormatter.localizedString(for: lastCheckedAt, relativeTo: Date())
    }

    private var yieldScoreDisplay: String {
        hasLastUpdated ? "\(yieldScore)" : "—"
    }

    private var riskScoreDisplay: String {
        hasLastUpdated ? "\(riskScore)" : "—"
    }

    private var exposureIndexDisplay: String {
        hasLastUpdated ? "\(exposureIndex)" : "—"
    }

    private var contributionScoreDisplay: String {
        hasLastUpdated ? "\(contributionScore)" : "—"
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
        case "home", "dashboard": return .dashboard
        case "intelligence", "network", "metrics": return .intelligence
        case "alerts": return .alerts
        case "feedback", "profile":
            return .profile
        case "map":
            return .profile
        case "activity": return .intelligence
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
                    .stroke(DesignSystem.Colors.accent.opacity(0.03), lineWidth: 0.45)

                Circle()
                    .fill(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: DesignSystem.Colors.accent.opacity(0.045), location: 0.07),
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
                    .opacity(0.55)
            }
            .opacity(0.036)
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
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                }

                Text(event.risk.reasons.first ?? "Review this activity for safety.")
                    .font(.caption)
                    .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.92))
                    .lineLimit(2)

                Text(event.detectedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.7))
            }

            Spacer(minLength: 6)

            Image(systemName: severity.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(severity.color.opacity(0.82))
        }
        .padding(14)
        .cardStyleLeft(cornerRadius: DesignSystem.Radius.xl)
}
}

private struct BottomDockItem: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
}

private struct BottomDock: View {
    let items: [BottomDockItem]
    @Binding var selectedID: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isSelected = item.id == selectedID
                Button {
                    onSelect(item.id)
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(DesignSystem.Colors.accent.opacity(isSelected ? 0.28 : 0))
                                .frame(width: 40, height: 40)
                                .blur(radius: isSelected ? 14 : 0)

                            Image(systemName: item.systemImage)
                                .font(.system(size: 23, weight: .medium))
                                .foregroundStyle(
                                    isSelected
                                        ? DesignSystem.Colors.accent
                                        : Color.white.opacity(0.78)
                                )
                                .shadow(
                                    color: isSelected
                                        ? DesignSystem.Colors.accent.opacity(0.75)
                                        : .clear,
                                    radius: 8,
                                    x: 0,
                                    y: 0
                                )
                        }
                        .frame(height: 28)

                        Circle()
                            .fill(DesignSystem.Colors.accent)
                            .frame(width: 5, height: 5)
                            .shadow(color: DesignSystem.Colors.accent.opacity(0.72), radius: 6, x: 0, y: 0)
                            .opacity(isSelected ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .frame(height: 78)
        .background {
            RoundedRectangle(cornerRadius: 39, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [ThemeTokens.Dock.top, ThemeTokens.Dock.bottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 39, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.06),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .init(x: 0.5, y: 0.35)
                            )
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 39, style: .continuous)
                        .strokeBorder(ThemeTokens.Dock.border, lineWidth: 1)
                }
        }
        .shadow(color: ThemeTokens.Dock.shadow, radius: 28, x: 0, y: 12)
        .shadow(color: DesignSystem.Colors.accent.opacity(0.08), radius: 28, x: 0, y: 0)
    }
}

private struct NFTThumbnailCell: View {
    let item: NFTItem

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [ThemeTokens.Card.top, ThemeTokens.Card.bottom],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 76, height: 76)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(
                                colors: [ThemeTokens.Card.innerHighlight, Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(ThemeTokens.Card.border, lineWidth: 0.75)
                    }

                if let url = item.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        case .failure:
                            nftPlaceholder
                        case .empty:
                            ProgressView()
                                .tint(DesignSystem.Colors.textMuted)
                        @unknown default:
                            nftPlaceholder
                        }
                    }
                } else {
                    nftPlaceholder
                }

                if item.isCompressed {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(3)
                                .background(DesignSystem.Colors.accent.opacity(0.85))
                                .clipShape(Circle())
                                .padding(4)
                        }
                    }
                    .frame(width: 76, height: 76)
                }
            }

            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 76)
        }
    }

    private var nftPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.22, blue: 0.24).opacity(0.90),
                    Color(red: 0.14, green: 0.14, blue: 0.16).opacity(0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(width: 76, height: 76)
    }
}

private struct ConnectWalletButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct RiskScoreProgressBar: View {
    let progress: Double

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let barWidth = max(0, geo.size.width * clampedProgress)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.10), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.72, green: 1.00, blue: 0.58),
                                DesignSystem.Colors.accent,
                                Color(red: 0.22, green: 0.86, blue: 0.18)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: barWidth)
                    .shadow(color: DesignSystem.Colors.accent.opacity(0.78), radius: 5, x: 0, y: 0)
                    .shadow(color: DesignSystem.Colors.accent.opacity(0.42), radius: 12, x: 0, y: 0)
            }
        }
        .frame(height: 12)
        .animation(.easeInOut(duration: 0.22), value: clampedProgress)
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

private struct SparklineView: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let points = normalizedPoints(in: geo.size)
            ZStack {
                Path { path in
                    path.addLines(points)
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 3)
                .blur(radius: 2)

                Path { path in
                    path.addLines(points)
                }
                .stroke(DesignSystem.Colors.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 1
        let range = max(maxValue - minValue, 0.001)

        return values.enumerated().map { index, value in
            let x = CGFloat(index) / CGFloat(max(values.count - 1, 1)) * size.width
            let normalizedY = (value - minValue) / range
            let y = size.height - (CGFloat(normalizedY) * size.height)
            return CGPoint(x: x, y: y)
        }
    }
}

struct MonitoringDot: View {
    var size: CGFloat = 8
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.green.opacity(0.9))
            .frame(width: size, height: size)
            .scaleEffect(isPulsing ? 1.14 : 0.88)
            .opacity(isPulsing ? 0.95 : 0.68)
            .onAppear { isPulsing = true }
            .animation(
                .easeInOut(duration: 1.2).repeatForever(),
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
                colors: [
                    Color(red: 0.10, green: 0.11, blue: 0.14),
                    Color(red: 0.05, green: 0.06, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Beta Test")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

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
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DesignSystem.Colors.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(DesignSystem.Colors.border, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Button("Got it") {
                        onDismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.black.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DesignSystem.Colors.accent)
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
                .fill(DesignSystem.Colors.accent)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
            Text(text)
                .font(.body)
                .foregroundStyle(DesignSystem.Colors.textSecondary)
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
                        .foregroundStyle(DesignSystem.Colors.danger)
                        .listRowBackground(DesignSystem.Colors.surface)
                }

                if let diagnosticsStatus {
                    Text(diagnosticsStatus)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .listRowBackground(DesignSystem.Colors.surface)
                }
            }
            .disabled(isDiagnosticsActionRunning)
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.11, blue: 0.14),
                        Color(red: 0.05, green: 0.06, blue: 0.08)
                    ],
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
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
        .listRowBackground(DesignSystem.Colors.surface)
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
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.body)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
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
            .background(DesignSystem.Colors.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.11, blue: 0.14),
                    Color(red: 0.05, green: 0.06, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}
