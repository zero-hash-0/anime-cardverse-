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
    @State private var animateBackground = false
    @State private var animateHeroGlow = false
    @State private var showHeroRadar = false
    @State private var showProfileEditor = false
    @State private var bottomTab: BottomDockTab = .home

    @AppStorage("profileDisplayName") private var profileDisplayName = "Guest"
    @AppStorage("profileStatusLine") private var profileStatusLine = "Get ready"
    @AppStorage("profileAvatarBase64") private var profileAvatarBase64 = ""

    private let themeBase = Color(red: 0.03, green: 0.03, blue: 0.04)
    private let themeMid = Color(red: 0.06, green: 0.06, blue: 0.07)
    private let themeDeep = Color(red: 0.01, green: 0.01, blue: 0.01)
    private let themeLime = Color(red: 0.83, green: 0.98, blue: 0.14)
    private let themeLimeSoft = Color(red: 0.70, green: 0.90, blue: 0.15)
    private let themeCard = Color(red: 0.09, green: 0.09, blue: 0.10)

    init(viewModel: DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        themeBase,
                        themeMid,
                        themeDeep
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                FloatingBubblesBackground(animate: animateBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topNav

                    ScrollView {
                        VStack(spacing: 16) {
                            header
                            topSectionPills

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
                        .padding(.top, 12)
                        .padding(.bottom, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .refreshable {
                        await viewModel.refreshSolanaNews()
                        await viewModel.refresh()
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .safeAreaInset(edge: .bottom, spacing: 8) {
                bottomActionBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
        }
        .task {
            await viewModel.onAppear()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                animateBackground.toggle()
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                animateHeroGlow.toggle()
            }
            showHeroRadar = true
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
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(profileStatusLine)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 8) {
                circleNavButton(systemName: "bell")
                circleNavButton(systemName: "magnifyingglass")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.5)
        }
    }

    private func circleNavButton(systemName: String) -> some View {
        Button {
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        ZStack(alignment: .leading) {
            RadarHeroBackdrop(animate: showHeroRadar)
                .frame(height: 88)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                Text("RADAR")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.white,
                                themeLime
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .shadow(color: themeLime.opacity(animateHeroGlow ? 0.40 : 0.14), radius: animateHeroGlow ? 16 : 8, y: 0)
                    .scaleEffect(animateHeroGlow ? 1.008 : 0.995)

                Text("Track Solana drops, risk alerts, and live market momentum.")
                    .font(.callout)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topSectionPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
                            .foregroundStyle(active ? Color.black.opacity(0.9) : .white.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(active ? themeLime : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var featuredMissionCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.black, Color(red: 0.12, green: 0.12, blue: 0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(themeLime.opacity(0.26), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text("New Update")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Text("Let’s crush your wallet risk profile today.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                HStack(spacing: 8) {
                    Label("15 min", systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.10))
                        .clipShape(Capsule())
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black.opacity(0.9))
                        .padding(8)
                        .background(themeLime)
                        .clipShape(Circle())
                }
            }
            .padding(14)
        }
        .frame(height: 190)
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
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var liveSnapshotCard: some View {
        HStack(spacing: 10) {
            snapshotItem(title: "Coverage", value: "\(viewModel.totalDetectedCount)", subtitle: "Tracked tokens")
            snapshotItem(title: "Threat", value: "\(threatPercentage)%", subtitle: "High-risk share")
            snapshotItem(title: "Watchlist", value: "\(viewModel.watchlistCount)", subtitle: "Starred mints")
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var smartInsightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Smart Insights")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(insightStatusTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(insightStatusColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(insightStatusColor.opacity(0.18))
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
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func insightRow(title: String, value: String, isGood: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isGood ? Color(red: 0.08, green: 0.84, blue: 0.58) : Color(red: 0.96, green: 0.80, blue: 0.46))
                .font(.caption)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.88))
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.67))
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
        if threatPercentage >= 45 { return Color(red: 1.0, green: 0.36, blue: 0.36) }
        if threatPercentage >= 20 { return Color(red: 0.96, green: 0.80, blue: 0.46) }
        return Color(red: 0.08, green: 0.84, blue: 0.58)
    }

    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(min(3, viewModel.displayedEvents.count)) items")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }

            if viewModel.displayedEvents.isEmpty {
                Text("No activity yet. Run a scan to generate a timeline.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))
            } else {
                ForEach(Array(viewModel.displayedEvents.prefix(3).enumerated()), id: \.element.id) { _, event in
                    activityRow(event)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func activityRow(_ event: AirdropEvent) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(riskColor(event.risk.level))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(event.metadata.symbol) +\(event.delta.description)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(event.detectedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.56))
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
        HStack(spacing: 12) {
            dockTabButton(.home, icon: "house")
            dockTabButton(.activity, icon: "calendar")

            Button {
                bottomTab = .checker
                topSection = .checker
                Task { await viewModel.refresh() }
            } label: {
                HStack(spacing: 4) {
                    if viewModel.isLoading {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text("Scan")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.black.opacity(0.92))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(themeLime)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            dockTabButton(.checker, icon: "scope")
            dockTabButton(.profile, icon: "person")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 14, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func dockTabButton(_ tab: BottomDockTab, icon: String) -> some View {
        let active = bottomTab == tab
        return Button {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                bottomTab = tab
                topSection = tab == .checker ? .checker : .dashboard
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(active ? Color.black.opacity(0.9) : Color.white.opacity(0.76))
                .frame(width: 34, height: 34)
                .background(active ? themeLime : Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
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
            summaryItem(title: "Total Events", value: "\(viewModel.totalDetectedCount)", tone: Color.white.opacity(0.08))
            summaryItem(title: "Watchlist", value: "\(viewModel.watchlistCount)", tone: Color(red: 0.96, green: 0.78, blue: 0.34).opacity(0.18))
            summaryItem(title: "High Risk", value: "\(viewModel.highRiskCount)", tone: Color(red: 1.0, green: 0.36, blue: 0.36).opacity(0.16))
        }
    }

    private func summaryItem(title: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.52))
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.95))
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
            WalletInputView(walletAddress: $viewModel.walletAddress)

            HStack(spacing: 10) {
                Button("Connect") {
                    viewModel.connectWallet()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.08, green: 0.84, blue: 0.58))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(red: 0.08, green: 0.84, blue: 0.58).opacity(0.16))
                .clipShape(Capsule())

                Button("Disconnect") {
                    viewModel.disconnectWallet()
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 1.0, green: 0.36, blue: 0.36))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(red: 1.0, green: 0.36, blue: 0.36).opacity(0.16))
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
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }

            summaryBoard

            Button {
                Task { await viewModel.refresh() }
            } label: {
                HStack {
                    if viewModel.isLoading {
                        ProgressView().tint(.black)
                    }
                    Text(viewModel.isLoading ? "Scanning..." : "Scan for Airdrops")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.black.opacity(0.9))
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.62, green: 0.92, blue: 1.0),
                        Color(red: 0.33, green: 0.86, blue: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: Color(red: 0.96, green: 0.78, blue: 0.34).opacity(0.35), radius: 14, y: 4)
            .shadow(color: Color(red: 0.33, green: 0.86, blue: 1.0).opacity(0.30), radius: 14, y: 4)
            .clipShape(Capsule())
            .disabled(viewModel.isLoading)

            Group {
                if showAdvancedControls && appLock.isUnlocked {
                    TextField("Search by token or mint", text: $viewModel.searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(11)
                        .foregroundStyle(.white)
                        .background(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    HStack(spacing: 14) {
                        Toggle("Alerts", isOn: $viewModel.notificationsEnabled)
                            .toggleStyle(.switch)
                            .tint(Color(red: 0.08, green: 0.84, blue: 0.58))
                            .onChange(of: viewModel.notificationsEnabled) { _ in
                                viewModel.persistNotificationPreference()
                            }

                        Toggle("Auto", isOn: $viewModel.autoScanEnabled)
                            .toggleStyle(.switch)
                            .tint(Color(red: 0.08, green: 0.84, blue: 0.58))
                            .onChange(of: viewModel.autoScanEnabled) { _ in
                                viewModel.persistAutoScanPreference()
                            }
                    }
                    .foregroundStyle(.white)

                    Toggle("High-risk alerts only", isOn: $viewModel.notifyHighRiskOnly)
                        .toggleStyle(.switch)
                        .tint(Color(red: 0.96, green: 0.78, blue: 0.34))
                        .foregroundStyle(.white)
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
                            .tint(Color(red: 0.96, green: 0.78, blue: 0.34))
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
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.selectedFilter != .latest {
                    Text("High risk: \(viewModel.highRiskCount)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                RiskDot(label: "Medium", value: viewModel.mediumRiskCount, color: Color(red: 0.14, green: 0.65, blue: 1.0))
                RiskDot(label: "High", value: viewModel.highRiskCount, color: Color(red: 1.0, green: 0.36, blue: 0.36))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            safetyPanel
        }
            .padding(14)
        .background(Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color(red: 0.33, green: 0.86, blue: 1.0).opacity(0.48),
                                Color.white.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color(red: 0.33, green: 0.86, blue: 1.0).opacity(0.16), radius: 18, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedFilter)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: showAdvancedControls)
    }

    private var newsBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.36, blue: 0.36))
                        .frame(width: 7, height: 7)
                    Text("Live Solana Pulse")
                        .font(.headline)
                }
                    .foregroundStyle(.white.opacity(0.96))
                Spacer()
                if !viewModel.solanaHeadlines.isEmpty {
                    Text("\(min(viewModel.activeHeadlineIndex + 1, viewModel.solanaHeadlines.count))/\(viewModel.solanaHeadlines.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }

            if let headline = viewModel.currentHeadline {
                Button {
                    UIApplication.shared.open(headline.url)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                    Text(headline.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .id(headline.id)
                            .transition(.move(edge: .trailing).combined(with: .opacity))

                        HStack(spacing: 8) {
                            Text(headline.source)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(red: 0.62, green: 0.92, blue: 1.0))
                                .lineLimit(1)
                            if let published = headline.publishedAt {
                                Text(published.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.58))
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
                                    .foregroundStyle(.white.opacity(0.92))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.white.opacity(0.08))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
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
                    .foregroundStyle(.white.opacity(0.7))
            }

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

                if let headline = viewModel.currentHeadline {
                    Button("Open Story") {
                        UIApplication.shared.open(headline.url)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(red: 0.08, green: 0.84, blue: 0.58).opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
