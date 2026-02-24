import SwiftUI
import UIKit
import PhotosUI

struct ContentView: View {
    private enum TopSection: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case checker = "Checker"

        var id: String { rawValue }
    }

    private enum BottomDockTab: String, CaseIterable, Identifiable {
        case home = "Home"
        case activity = "Activity"
        case checker = "Checker"
        case profile = "Profile"

        var id: String { rawValue }
    }

    @StateObject private var viewModel: DashboardViewModel
    @EnvironmentObject private var appLock: AppLockManager
    @EnvironmentObject private var accessManager: ActivationAccessManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var topSection: TopSection = .checker
    @State private var showAdvancedControls = false
    @State private var showProfileEditor = false
    @State private var bottomTab: BottomDockTab = .home
    @FocusState private var walletFieldFocused: Bool
    @State private var hitTestDebugMode = false

    @AppStorage("profileDisplayName") private var profileDisplayName = "Guest"
    @AppStorage("profileStatusLine") private var profileStatusLine = "Get ready"
    @AppStorage("profileAvatarBase64") private var profileAvatarBase64 = ""

    private let themeBase = RadarTheme.Palette.backgroundTop
    private let themeMid = Color(red: 0.02, green: 0.02, blue: 0.03)
    private let themeDeep = RadarTheme.Palette.backgroundBottom
    private let themeLime = RadarTheme.Palette.accent
    private let themeLimeSoft = RadarTheme.Palette.accentAlt
    private let themeCard = RadarTheme.Palette.surface
    private let dockHeight: CGFloat = 78

    init(viewModel: DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                backgroundLayers

                VStack(spacing: 0) {
                    topNav

                    ScrollViewReader { reader in
                        ScrollView {
                            VStack(spacing: 16) {
                                header
                                topSectionPills
                                contextChipRail

                                if bottomTab == .home {
                                    featuredMissionCard
                                    quickActionsCard
                                    liveSnapshotCard
                                    smartInsightsCard
                                }

                                if bottomTab == .activity {
                                    newsBanner
                                    recentActivityCard
                                    AirdropListView(
                                        events: viewModel.displayedEvents,
                                        emptyTitle: emptyStateTitle,
                                        emptySubtitle: emptyStateSubtitle,
                                        isFavorite: { mint in
                                            viewModel.isFavorite(mint: mint)
                                        },
                                        onToggleFavorite: { mint in
                                            viewModel.toggleFavorite(mint: mint)
                                        },
                                        onHideToken: { mint in
                                            viewModel.hideMint(mint)
                                        }
                                    )
                                }

                                if bottomTab == .checker || topSection == .checker {
                                    controlCard
                                        .id("controlCard")
                                    AirdropListView(
                                        events: viewModel.displayedEvents,
                                        emptyTitle: emptyStateTitle,
                                        emptySubtitle: emptyStateSubtitle,
                                        isFavorite: { mint in
                                            viewModel.isFavorite(mint: mint)
                                        },
                                        onToggleFavorite: { mint in
                                            viewModel.toggleFavorite(mint: mint)
                                        },
                                        onHideToken: { mint in
                                            viewModel.hideMint(mint)
                                        }
                                    )
                                }

                                if bottomTab == .profile {
                                    profileHubCard
                                    securityCenterCard
                                    themePreviewCard
                                }

                                if viewModel.selectedFilter == .history || viewModel.selectedFilter == .highRisk {
                                    Button("Clear History") {
                                        viewModel.clearHistory()
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, dockHeight + proxy.safeAreaInsets.bottom + 24)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .onChange(of: walletFieldFocused) { focused in
                            guard focused else { return }
                            withAnimation(.easeOut(duration: 0.22)) {
                                reader.scrollTo("controlCard", anchor: .bottom)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .refreshable {
                        await viewModel.refreshSolanaNews()
                        await viewModel.refresh()
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .zIndex(1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 8) {
                bottomActionBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .overlay(alignment: .topTrailing) {
#if DEBUG
                Text(buildLabel)
                    .font(.caption2.monospaced())
                    .foregroundStyle(RadarTheme.Palette.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RadarTheme.Palette.surface)
                    .overlay(
                        Capsule().stroke(RadarTheme.Palette.stroke, lineWidth: 1)
                    )
                    .clipShape(Capsule())
                    .padding(.top, 6)
                    .padding(.trailing, 16)
                    .allowsHitTesting(false)
#endif
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    if hitTestDebugMode {
                        print("HitTestDebug: RADAR root tap reached content")
                    }
                }
            )
        }
        .task {
            await viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onOpenURL { url in
            viewModel.handleWalletURL(url)
        }
        .onChange(of: scenePhase) { newPhase in
            appLock.handleScenePhaseChange(newPhase)
        }
        .onChange(of: appLock.isUnlocked) { isUnlocked in
            if !isUnlocked && showAdvancedControls {
                showAdvancedControls = false
            }
        }
        .sheet(isPresented: $showProfileEditor) {
            ProfileEditorSheet(
                name: $profileDisplayName,
                statusLine: $profileStatusLine,
                avatarBase64: $profileAvatarBase64,
                accent: themeLime
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    walletFieldFocused = false
                }
            }
        }
    }

    private var buildLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(version) (\(build))"
    }

    private var topNav: some View {
        return HStack(alignment: .center, spacing: 12) {
            Button {
                showProfileEditor = true
            } label: {
                HStack(spacing: 10) {
                    profileAvatar(size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profileDisplayName)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(RadarTheme.Palette.textPrimary)
                            .lineLimit(1)
                        Text(profileStatusLine)
                            .font(.caption2)
                            .foregroundStyle(RadarTheme.Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 8) {
                circleNavButton(systemName: "bell") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await viewModel.refreshSolanaNews() }
                }
                circleNavButton(systemName: "magnifyingglass") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    bottomTab = .checker
                    topSection = .checker
                    showAdvancedControls = true
                    walletFieldFocused = true
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func circleNavButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(RadarTheme.Palette.textPrimary)
                .frame(width: 34, height: 34)
                .background(RadarTheme.Palette.surfaceStrong)
                .clipShape(Circle())
                .overlay(Circle().stroke(RadarTheme.Palette.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hello \(profileDisplayName)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(RadarTheme.Palette.textPrimary)
            Text("Get ready")
                .font(.caption)
                .foregroundStyle(RadarTheme.Palette.textSecondary)
            Text("RADAR")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(RadarTheme.Palette.textPrimary)
                .onLongPressGesture(minimumDuration: 1.0) {
                    #if DEBUG
                    hitTestDebugMode.toggle()
                    print("HitTestDebug: \(hitTestDebugMode ? "ON" : "OFF")")
                    #endif
                }
            Text("Track Solana drops, risk alerts, and live market momentum.")
                .font(RadarTheme.Typography.body)
                .foregroundStyle(RadarTheme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topSectionPills: some View {
        HStack(spacing: 10) {
            ForEach(TopSection.allCases) { section in
                let active = topSection == section
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                        topSection = section
                        bottomTab = section == .checker ? .checker : .home
                    }
                } label: {
                    Text(section.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(active ? Color.black.opacity(0.9) : RadarTheme.Palette.textSecondary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(active ? RadarTheme.Palette.accent : RadarTheme.Palette.surfaceStrong.opacity(0.65))
                        .overlay(
                            Capsule().stroke(active ? RadarTheme.Palette.accent.opacity(0.40) : RadarTheme.Palette.stroke, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var contextChipRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Text("New")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.black.opacity(0.9))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(RadarTheme.Palette.accent)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                ForEach(["Fast", "Risk", "Watchlist", "On-chain"], id: \.self) { chip in
                    Button {
                        print("Selected chip: \(chip)")
                    } label: {
                        Text(chip)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(RadarTheme.Palette.textSecondary)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(RadarTheme.Palette.surface)
                            .overlay(Capsule().stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                            .clipShape(Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var featuredMissionCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.76), Color.black.opacity(0.46)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [RadarTheme.Palette.accent.opacity(0.28), .clear],
                                startPoint: .topLeading,
                                endPoint: .center
                            )
                        )
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(RadarTheme.Palette.stroke, lineWidth: 1)
                )

            VStack(spacing: 0) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: 120)
                    .overlay(
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(Color.white.opacity(0.22))
                    )
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("New Update")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                Text("Let’s crush your wallet risk profile today.")
                    .font(.subheadline)
                    .foregroundStyle(RadarTheme.Palette.textSecondary)
                HStack(spacing: 8) {
                    Label("15 min", systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RadarTheme.Palette.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RadarTheme.Palette.surface)
                        .overlay(Capsule().stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                        .clipShape(Capsule())
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.black.opacity(0.85))
                        .padding(8)
                        .background(RadarTheme.Palette.accent)
                        .clipShape(Circle())
                }
            }
            .padding(14)
        }
        .frame(height: 250)
        .shadow(color: Color.black.opacity(0.25), radius: 12, y: 6)
    }

    private var profileHubCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                profileAvatar(size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(profileDisplayName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Text(profileStatusLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                }
                Spacer()
                Button("Edit") { showProfileEditor = true }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(themeLime)
                    .clipShape(Capsule())
            }

            Button("Sign Out Access") {
                accessManager.deactivate()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.10))
            .clipShape(Capsule())
        }
        .padding(14)
        .background(themeCard.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(themeLime.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var themePreviewCard: some View {
        VStack(alignment: .leading, spacing: RadarTheme.Spacing.sm) {
            Text("Theme Preview")
                .font(RadarTheme.Typography.headline)
                .foregroundStyle(RadarTheme.Palette.textPrimary)

            Text("Glass surfaces, focused accents, and cleaner hierarchy.")
                .font(RadarTheme.Typography.caption)
                .foregroundStyle(RadarTheme.Palette.textSecondary)

            HStack(spacing: RadarTheme.Spacing.xs) {
                Text("Primary")
                    .font(RadarTheme.Typography.caption.weight(.bold))
                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [RadarTheme.Palette.accent, RadarTheme.Palette.accentAlt],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())

                Text("Secondary")
                    .font(RadarTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(RadarTheme.Palette.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RadarTheme.Palette.surface)
                    .overlay(Capsule().stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                    .clipShape(Capsule())
            }
        }
        .padding(RadarTheme.Spacing.sm)
        .radarGlassCard()
    }

    private var quickActionsCard: some View {
        HStack(spacing: 8) {
            quickActionButton(title: "Copy Wallet", icon: "doc.on.doc") {
                let trimmed = viewModel.walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                UIPasteboard.general.string = trimmed
            }

            quickActionButton(title: "Solscan", icon: "safari") {
                guard let walletExplorerURL else { return }
                UIApplication.shared.open(walletExplorerURL)
            }

            quickActionButton(title: "Jupiter", icon: "arrow.up.right.square") {
                guard let jupiterURL else { return }
                UIApplication.shared.open(jupiterURL)
            }
        }
    }

    private func quickActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(RadarTheme.Palette.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(RadarTheme.Palette.surfaceStrong.opacity(0.85))
            .overlay(
                Capsule()
                    .stroke(RadarTheme.Palette.stroke, lineWidth: 1)
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var liveSnapshotCard: some View {
        HStack(spacing: 10) {
            snapshotItem(title: "Coverage", value: "\(viewModel.totalDetectedCount)", subtitle: "Tracked tokens")
            Divider().overlay(Color.white.opacity(0.08))
            snapshotItem(title: "Threat", value: "\(threatPercentage)%", subtitle: "High-risk share")
            Divider().overlay(Color.white.opacity(0.08))
            snapshotItem(title: "Watchlist", value: "\(viewModel.watchlistCount)", subtitle: "Starred mints")
        }
        .padding(12)
        .radarGlassCard(cornerRadius: 16)
    }

    private var smartInsightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Smart Insights")
                    .font(.headline)
                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                Spacer()
                Text(insightStatusTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(insightStatusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(insightStatusColor.opacity(0.12))
                    .overlay(Capsule().stroke(insightStatusColor.opacity(0.6), lineWidth: 1))
                    .clipShape(Capsule())
            }

            insightRow(
                title: "Wallet Hygiene",
                value: viewModel.hasValidWalletAddress ? "Connected and validated." : "Add a wallet to unlock full scan intelligence.",
                isGood: viewModel.hasValidWalletAddress
            )
            insightRow(
                title: "Risk Pressure",
                value: threatPercentage >= 35 ? "Elevated high-risk ratio. Tighten filters and verify mints." : "Risk levels are stable right now.",
                isGood: threatPercentage < 35
            )
            insightRow(
                title: "Market Focus",
                value: viewModel.popularTopics.first.map { "Trending: \($0)." } ?? "No strong topic concentration yet.",
                isGood: true
            )
        }
        .padding(12)
        .radarGlassCard(cornerRadius: 16)
    }

    private func insightRow(title: String, value: String, isGood: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isGood ? "checkmark" : "exclamationmark")
                .foregroundStyle(isGood ? RadarTheme.Palette.success : RadarTheme.Palette.warning)
                .font(.caption)
                .frame(width: 20, height: 20)
                .padding(6)
                .background(RadarTheme.Palette.surfaceStrong)
                .overlay(Circle().stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                .clipShape(Circle())
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(RadarTheme.Palette.textSecondary)
            }
            Spacer()
        }
    }

    private var insightStatusTitle: String {
        if threatPercentage >= 45 { return "Caution" }
        if threatPercentage >= 20 { return "Watch" }
        return "Stable"
    }

    private var insightStatusColor: Color {
        if threatPercentage >= 45 { return RadarTheme.Palette.warning }
        if threatPercentage >= 20 { return RadarTheme.Palette.warning }
        return RadarTheme.Palette.success
    }

    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                Spacer()
                Text("\(min(3, viewModel.displayedEvents.count)) items")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RadarTheme.Palette.textSecondary)
            }

            if viewModel.displayedEvents.isEmpty {
                Text("No activity yet. Run a scan to generate a timeline.")
                    .font(.caption)
                    .foregroundStyle(RadarTheme.Palette.textSecondary)
            } else {
                ForEach(Array(viewModel.displayedEvents.prefix(3).enumerated()), id: \.element.id) { _, event in
                    activityRow(event)
                }
            }
        }
        .padding(12)
        .radarGlassCard(cornerRadius: 16)
    }

    private func activityRow(_ event: AirdropEvent) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(riskColor(event.risk.level))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(event.metadata.symbol) +\(event.delta.description)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                Text(event.detectedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(RadarTheme.Palette.textSecondary)
            }
            Spacer()
            Text(event.risk.level.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(riskColor(event.risk.level).opacity(0.85))
                .clipShape(Capsule())
        }
    }

    private func riskColor(_ level: ClaimRiskLevel) -> Color {
        switch level {
        case .low:
            return Color(red: 0.08, green: 0.84, blue: 0.58)
        case .medium:
            return Color(red: 0.96, green: 0.80, blue: 0.46)
        case .high:
            return Color(red: 1.0, green: 0.36, blue: 0.36)
        }
    }

    private var bottomActionBar: some View {
        HStack(spacing: 10) {
            dockTabButton(.home, icon: "house")
            dockTabButton(.activity, icon: "calendar")
            dockTabButton(.checker, icon: "scope")
            dockTabButton(.profile, icon: "person")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.30), radius: 18, y: 10)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func dockTabButton(_ tab: BottomDockTab, icon: String) -> some View {
        let active = bottomTab == tab
        return Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                bottomTab = tab
                topSection = tab == .checker ? .checker : .dashboard
            }
            if tab == .checker {
                Task { await viewModel.refresh() }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                if active {
                    Text(tab.rawValue)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(active ? Color.black.opacity(0.90) : RadarTheme.Palette.textSecondary)
            .padding(.horizontal, active ? 12 : 0)
            .frame(width: active ? nil : 34, height: 34)
            .background(active ? RadarTheme.Palette.accent : RadarTheme.Palette.surface)
            .overlay(
                Capsule().stroke(active ? RadarTheme.Palette.accent.opacity(0.45) : RadarTheme.Palette.stroke, lineWidth: 1)
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var backgroundLayers: some View {
        ZStack {
            LinearGradient(
                colors: [themeBase, themeMid, themeDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [themeLime.opacity(0.10), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 340
            )
            .blur(radius: 14)
            .ignoresSafeArea()

            RadialGradient(
                colors: [themeLimeSoft.opacity(0.08), .clear],
                center: .bottomTrailing,
                startRadius: 40,
                endRadius: 320
            )
            .blur(radius: 12)
            .ignoresSafeArea()

#if DEBUG
            if hitTestDebugMode {
                Rectangle()
                    .fill(Color.red.opacity(0.09))
                    .ignoresSafeArea()
                    .overlay(alignment: .topLeading) {
                        Text("Hit-Test Debug: Background Layers")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(Color.black.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(12)
                    }
            }
#endif
        }
        .allowsHitTesting(false)
    }

    private func snapshotItem(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var threatPercentage: Int {
        guard viewModel.totalDetectedCount > 0 else { return 0 }
        return Int((Double(viewModel.highRiskCount) / Double(viewModel.totalDetectedCount)) * 100)
    }

    private var walletExplorerURL: URL? {
        let trimmed = viewModel.walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "https://solscan.io/account/\(trimmed)")
    }

    private func profileAvatar(size: CGFloat) -> some View {
        ZStack {
            if let avatar = UIImage.fromBase64(profileAvatarBase64) {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [themeLime.opacity(0.92), themeLimeSoft.opacity(0.70)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text(profileInitials)
                    .font(.system(size: max(11, size * 0.34), weight: .black, design: .rounded))
                    .foregroundStyle(.black.opacity(0.90))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }

    private var profileInitials: String {
        let parts = profileDisplayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .prefix(2)
        let initials = parts.compactMap { $0.first }.map(String.init).joined()
        return initials.isEmpty ? "R" : initials.uppercased()
    }

    private var jupiterURL: URL? {
        let trimmed = viewModel.walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "https://jup.ag/portfolio/\(trimmed)")
    }

    private var summaryBoard: some View {
        HStack(spacing: 10) {
            summaryItem(title: "Total Events", value: "\(viewModel.totalDetectedCount)", tone: RadarTheme.Palette.surface)
            summaryItem(title: "Watchlist", value: "\(viewModel.watchlistCount)", tone: RadarTheme.Palette.accent.opacity(0.18))
            summaryItem(title: "High Risk", value: "\(viewModel.highRiskCount)", tone: RadarTheme.Palette.warning.opacity(0.18))
        }
    }

    private func summaryItem(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(RadarTheme.Palette.textSecondary)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(RadarTheme.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var controlCard: some View {
        VStack(spacing: 12) {
            WalletInputView(walletAddress: $viewModel.walletAddress, isFocused: $walletFieldFocused)

            HStack(spacing: 10) {
                Button("Connect") {
                    viewModel.connectWallet()
                }
                .buttonStyle(.plain)
                .foregroundStyle(RadarTheme.Palette.success)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(RadarTheme.Palette.success.opacity(0.16))
                .overlay(Capsule().stroke(RadarTheme.Palette.success.opacity(0.55), lineWidth: 1))
                .clipShape(Capsule())

                Button("Disconnect") {
                    viewModel.disconnectWallet()
                }
                .buttonStyle(.plain)
                .foregroundStyle(RadarTheme.Palette.danger)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(RadarTheme.Palette.danger.opacity(0.16))
                .overlay(Capsule().stroke(RadarTheme.Palette.danger.opacity(0.55), lineWidth: 1))
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EventFeedFilter.allCases) { filter in
                        FeedChip(
                            title: filter.title,
                            active: viewModel.selectedFilter == filter
                        ) {
                            viewModel.selectedFilter = filter
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button(showAdvancedControls ? "Basic" : "Advanced") {
                    if showAdvancedControls {
                        showAdvancedControls = false
                    } else {
                        Task {
                            let unlocked = await appLock.ensureUnlocked(reason: "Unlock advanced security controls.")
                            if unlocked {
                                showAdvancedControls = true
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RadarTheme.Palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RadarTheme.Palette.surface)
                .overlay(Capsule().stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                .clipShape(Capsule())
            }

            summaryBoard

            Button {
                Task { await viewModel.refresh() }
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView().tint(RadarTheme.Palette.textPrimary)
                    }
                    Text(viewModel.isLoading ? "Scanning..." : "Scan for Airdrops")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(RadarTheme.Palette.textPrimary)
            .background(
                LinearGradient(
                    colors: [
                        RadarTheme.Palette.accent,
                        RadarTheme.Palette.accentAlt
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: RadarTheme.Palette.accent.opacity(0.32), radius: 12, y: 5)
            .clipShape(Capsule())
            .disabled(viewModel.isLoading)

            Group {
                if showAdvancedControls && appLock.isUnlocked {
                    TextField("Search by token or mint", text: $viewModel.searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(11)
                        .foregroundStyle(RadarTheme.Palette.textPrimary)
                        .background(RadarTheme.Palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(RadarTheme.Palette.stroke, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    HStack(spacing: 14) {
                        Toggle("Alerts", isOn: $viewModel.notificationsEnabled)
                            .toggleStyle(.switch)
                            .tint(RadarTheme.Palette.success)
                            .onChange(of: viewModel.notificationsEnabled) { _ in
                                viewModel.persistNotificationPreference()
                            }

                        Toggle("Auto", isOn: $viewModel.autoScanEnabled)
                            .toggleStyle(.switch)
                            .tint(RadarTheme.Palette.success)
                            .onChange(of: viewModel.autoScanEnabled) { _ in
                                viewModel.persistAutoScanPreference()
                            }
                    }
                    .foregroundStyle(RadarTheme.Palette.textPrimary)

                    Toggle("High-risk alerts only", isOn: $viewModel.notifyHighRiskOnly)
                        .toggleStyle(.switch)
                        .tint(RadarTheme.Palette.warning)
                        .foregroundStyle(RadarTheme.Palette.textPrimary)
                        .onChange(of: viewModel.notifyHighRiskOnly) { _ in
                            viewModel.persistHighRiskAlertPreference()
                        }

                    HStack {
                        Button("Load Demo Results") {
                            viewModel.loadDemoData()
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)

                        if !viewModel.hiddenMints.isEmpty {
                            Button("Unhide \(viewModel.hiddenMints.count)") {
                                viewModel.unhideAllMints()
                            }
                            .buttonStyle(.bordered)
                            .tint(RadarTheme.Palette.warning)
                        }

                        Spacer()
                    }
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))

            HStack {
                if let checkedAt = viewModel.lastCheckedAt {
                    Text("Last scan: \(checkedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(RadarTheme.Palette.textSecondary)
                }

                Spacer()

                if viewModel.selectedFilter != .latest {
                    Text("High risk: \(viewModel.highRiskCount)")
                        .font(.footnote)
                        .foregroundStyle(RadarTheme.Palette.textSecondary)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                RiskDot(label: "Low", value: viewModel.lowRiskCount, color: Color(red: 0.08, green: 0.84, blue: 0.58))
                RiskDot(label: "Medium", value: viewModel.mediumRiskCount, color: RadarTheme.Palette.accent)
                RiskDot(label: "High", value: viewModel.highRiskCount, color: RadarTheme.Palette.danger)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            safetyPanel
        }
            .padding(14)
        .radarGlassCard(cornerRadius: 18)
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedFilter)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: showAdvancedControls)
    }

    private var newsBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(RadarTheme.Palette.accent)
                        .frame(width: 7, height: 7)
                    Text("Live Solana Pulse")
                        .font(.headline)
                }
                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                Spacer()
                if !viewModel.solanaHeadlines.isEmpty {
                    Text("\(min(viewModel.activeHeadlineIndex + 1, viewModel.solanaHeadlines.count))/\(viewModel.solanaHeadlines.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RadarTheme.Palette.textSecondary)
                }
            }

            if let headline = viewModel.currentHeadline {
                Button {
                    UIApplication.shared.open(headline.url)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                    Text(headline.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(RadarTheme.Palette.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .id(headline.id)
                            .transition(.move(edge: .trailing).combined(with: .opacity))

                        HStack(spacing: 8) {
                            Text(headline.source)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(RadarTheme.Palette.accent)
                                .lineLimit(1)
                            if let published = headline.publishedAt {
                                Text(published.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(RadarTheme.Palette.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if !viewModel.popularTopics.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.popularTopics, id: \.self) { topic in
                                Button {
                                    openTopic(topic)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "flame.fill")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(topic)
                                            .font(.caption.weight(.semibold))
                                    }
                                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(RadarTheme.Palette.surface)
                                    .overlay(Capsule().stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else {
                Text(viewModel.newsStatusMessage ?? "Loading live Solana headlines...")
                    .font(.footnote)
                    .foregroundStyle(RadarTheme.Palette.textSecondary)
            }

            HStack(spacing: 8) {
                Button("Refresh News") {
                    Task { await viewModel.refreshSolanaNews() }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RadarTheme.Palette.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RadarTheme.Palette.surface)
                .overlay(Capsule().stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                .clipShape(Capsule())

                if let headline = viewModel.currentHeadline {
                    Button("Open Story") {
                        UIApplication.shared.open(headline.url)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RadarTheme.Palette.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(RadarTheme.Palette.surface)
                    .overlay(Capsule().stroke(RadarTheme.Palette.stroke, lineWidth: 1))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .radarGlassCard(cornerRadius: 18)
        .animation(.easeInOut(duration: 0.35), value: viewModel.currentHeadline?.id)
    }

    private var securityCenterCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(Color(red: 0.96, green: 0.80, blue: 0.46))
                    Text("Security Center")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Spacer()
                Text("\(viewModel.securityScore)%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(securityScoreColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(securityScoreColor.opacity(0.16))
                    .clipShape(Capsule())
            }

            if appLock.isUnlocked {
                securityStatusRow(
                    title: "Wallet",
                    detail: viewModel.hasValidWalletAddress ? "Valid Solana address connected." : "Connect a valid wallet address.",
                    isGood: viewModel.hasValidWalletAddress
                )
                securityStatusRow(
                    title: "Alerts",
                    detail: viewModel.notificationsEnabled ? "Local notifications enabled." : "Notifications are disabled.",
                    isGood: viewModel.notificationsEnabled
                )

                HStack(spacing: 8) {
                    Button("Refresh News") {
                        Task { await viewModel.refreshSolanaNews() }
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())

                    Spacer()
                }
            } else {
                Text("Security controls are locked. Unlock with \(appLock.biometryDisplayName) to view or edit sensitive settings.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                Button("Unlock Security") {
                    Task {
                        _ = await appLock.ensureUnlocked(reason: "Unlock security center controls.")
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.96, green: 0.80, blue: 0.46).opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var securityScoreColor: Color {
        if viewModel.securityScore >= 80 {
            return Color(red: 0.08, green: 0.84, blue: 0.58)
        }
        if viewModel.securityScore >= 60 {
            return Color(red: 0.96, green: 0.80, blue: 0.46)
        }
        return Color(red: 1.0, green: 0.36, blue: 0.36)
    }

    private func securityStatusRow(title: String, detail: String, isGood: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isGood ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isGood ? Color(red: 0.08, green: 0.84, blue: 0.58) : Color(red: 1.0, green: 0.36, blue: 0.36))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer()
        }
    }

    private func openTopic(_ topic: String) {
        let query = "solana \(topic)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "solana"
        if let url = URL(string: "https://news.google.com/search?q=\(query)&hl=en-US&gl=US&ceid=US:en") {
            UIApplication.shared.open(url)
        }
    }

    private var safetyPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(Color(red: 0.96, green: 0.78, blue: 0.34))
                Text("Safety Checklist")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }

            Text("1. Never sign unknown claim transactions.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.74))
            Text("2. Treat tiny dust deposits as potential phishing bait.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.74))
            Text("3. Verify token mint on Solscan before interacting.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.74))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(red: 0.96, green: 0.78, blue: 0.34).opacity(0.26), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyStateTitle: String {
        switch viewModel.selectedFilter {
        case .watchlist:
            return "No Watchlist Events"
        case .highRisk:
            return "No High-Risk Events"
        case .history:
            return "No History Yet"
        case .latest:
            return "No Airdrop Events Yet"
        }
    }

    private var emptyStateSubtitle: String {
        switch viewModel.selectedFilter {
        case .watchlist:
            return "Star tokens from the feed to track your favorites in one place."
        case .highRisk:
            return "Run another scan after wallet activity to check for risky claims."
        case .history:
            return "Scan your wallet or load demo results to build event history."
        case .latest:
            return "Run a scan or load demo results to inspect events and risk scores."
        }
    }

}

private struct RadarHeroBackdrop: View {
    let animate: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Circle()
                .trim(from: 0.15, to: 0.95)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.96, green: 0.80, blue: 0.46).opacity(0.0),
                            Color(red: 0.96, green: 0.80, blue: 0.46).opacity(0.35),
                            Color(red: 0.08, green: 0.84, blue: 0.58).opacity(0.45)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(animate ? 360 : 0))
                .offset(x: -58, y: -28)

            Circle()
                .fill(Color(red: 0.08, green: 0.84, blue: 0.58).opacity(0.18))
                .frame(width: 11, height: 11)
                .offset(x: animate ? 66 : 18, y: animate ? 14 : 42)
                .shadow(color: Color(red: 0.08, green: 0.84, blue: 0.58).opacity(0.7), radius: 10)
        }
        .animation(.linear(duration: 10).repeatForever(autoreverses: false), value: animate)
    }
}

private struct FloatingBubblesBackground: View {
    let animate: Bool

    var body: some View {
        ZStack {
            BubbleOrb(
                color: Color(red: 0.37, green: 0.90, blue: 1.0).opacity(0.26),
                size: 250,
                xFrom: -120,
                xTo: 70,
                yFrom: 260,
                yTo: 120,
                animate: animate
            )
            BubbleOrb(
                color: Color(red: 0.66, green: 0.80, blue: 1.0).opacity(0.22),
                size: 210,
                xFrom: 160,
                xTo: 20,
                yFrom: -220,
                yTo: -120,
                animate: animate
            )
            BubbleOrb(
                color: Color.white.opacity(0.10),
                size: 140,
                xFrom: -160,
                xTo: -40,
                yFrom: -120,
                yTo: 40,
                animate: animate
            )
            BubbleOrb(
                color: Color(red: 0.52, green: 0.96, blue: 0.95).opacity(0.14),
                size: 170,
                xFrom: 170,
                xTo: 70,
                yFrom: 260,
                yTo: 170,
                animate: animate
            )
        }
    }
}

private struct BubbleOrb: View {
    let color: Color
    let size: CGFloat
    let xFrom: CGFloat
    let xTo: CGFloat
    let yFrom: CGFloat
    let yTo: CGFloat
    let animate: Bool

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .blur(radius: 30)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    .blur(radius: 1)
            )
            .offset(x: animate ? xTo : xFrom, y: animate ? yTo : yFrom)
            .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: animate)
    }
}

private struct FeedChip: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        let textColor = active ? Color.white : Color.white.opacity(0.75)
        let fillColor = active ? Color(red: 0.33, green: 0.86, blue: 1.0).opacity(0.22) : Color.white.opacity(0.06)
        let borderColor = active ? Color.white.opacity(0.28) : Color.white.opacity(0.10)

        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(textColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .background(fillColor)
                .overlay(Capsule().stroke(borderColor, lineWidth: 1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct RiskDot: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text("\(label): \(value)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.74))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.04))
        .clipShape(Capsule())
    }
}

private struct ProfileEditorSheet: View {
    @Binding var name: String
    @Binding var statusLine: String
    @Binding var avatarBase64: String
    let accent: Color

    @Environment(\.dismiss) private var dismiss
    @State private var draftName = ""
    @State private var draftStatus = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var draftAvatarImage: UIImage?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    avatarPreview
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profile")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Customize your identity for Radar.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.66))
                    }
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose Photo", systemImage: "photo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black.opacity(0.9))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(accent)
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Display Name")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.76))
                    TextField("Your name", text: $draftName)
                        .textInputAutocapitalization(.words)
                        .padding(12)
                        .foregroundStyle(.white)
                        .background(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Status")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.76))
                    TextField("Get ready", text: $draftStatus)
                        .textInputAutocapitalization(.sentences)
                        .padding(12)
                        .foregroundStyle(.white)
                        .background(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.06),
                        Color(red: 0.01, green: 0.01, blue: 0.02)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        name = draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Guest" : draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                        statusLine = draftStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Get ready" : draftStatus.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .foregroundStyle(accent)
                    .fontWeight(.bold)
                }
            }
        }
        .onAppear {
            draftName = name
            draftStatus = statusLine
            draftAvatarImage = UIImage.fromBase64(avatarBase64)
        }
        .onChange(of: selectedPhoto) { item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                await MainActor.run {
                    draftAvatarImage = image
                    avatarBase64 = data.base64EncodedString()
                }
            }
        }
    }

    private var avatarPreview: some View {
        ZStack {
            if let draftAvatarImage {
                Image(uiImage: draftAvatarImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(accent.opacity(0.92))
                Text(initials)
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.black.opacity(0.92))
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
    }

    private var initials: String {
        let parts = draftName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .prefix(2)
        let value = parts.compactMap { $0.first }.map(String.init).joined()
        return value.isEmpty ? "R" : value.uppercased()
    }
}

private extension UIImage {
    static func fromBase64(_ value: String) -> UIImage? {
        guard let data = Data(base64Encoded: value), !data.isEmpty else { return nil }
        return UIImage(data: data)
    }
}
