import CryptoKit
import Foundation
import UIKit

enum WalletConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(String)
    case error(String)
}

enum NFTCountLoadState: Equatable {
    case idle
    case loading
    case success
    case failure
}

enum ScanStatus: Equatable {
    case idle
    case scanning
    case success(Date)
    case failure(String)
}

enum RefreshTrigger: String {
    case manual
    case pullToRefresh
    case autoScan
    case initial
    case retry
}

private extension WalletConnectionState {
    var debugLabel: String {
        switch self {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .error(let message): return "error(\(message))"
        }
    }
}

private extension ScanStatus {
    var debugLabel: String {
        switch self {
        case .idle: return "idle"
        case .scanning: return "scanning"
        case .success(let date): return "success(\(date.timeIntervalSince1970))"
        case .failure(let message): return "failure(\(message))"
        }
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var walletAddress = "" {
        didSet {
            if oldValue.trimmingCharacters(in: .whitespacesAndNewlines) != walletAddress.trimmingCharacters(in: .whitespacesAndNewlines) {
                nftCounts = .zero
                nftCount = 0
                nftCountLoadState = .idle
                nftItems = []
                walletValidationMessage = nil
                statusMessage = nil
                didRunPostPaintInitialScan = false
                clearRefreshState(resetLastCheckedAt: true)
            }
        }
    }
    @Published var latestEvents: [AirdropEvent] = []
    @Published var historyEvents: [AirdropEvent] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var errorMessage: String? {
        didSet {
#if DEBUG
            guard oldValue != errorMessage else { return }
            scanLog("errorMessage: \(oldValue ?? "nil") -> \(errorMessage ?? "nil")")
#endif
        }
    }
    @Published var lastCheckedAt: Date?
    @Published var lastRefreshError: String? {
        didSet {
#if DEBUG
            guard oldValue != lastRefreshError else { return }
            scanLog("lastRefreshError: \(oldValue ?? "nil") -> \(lastRefreshError ?? "nil")")
#endif
        }
    }
    @Published var scanStatus: ScanStatus = .idle {
        didSet {
#if DEBUG
            guard oldValue != scanStatus else { return }
            scanLog("scanStatus: \(oldValue.debugLabel) -> \(scanStatus.debugLabel)")
#endif
        }
    }
    @Published private(set) var showActionableScanFailure = false
    @Published private(set) var passiveScanFailureMessage: String?
    @Published var notificationsEnabled = true
    @Published var notifyHighRiskOnly = false
    @Published var autoScanEnabled = false
    @Published var selectedFilter: EventFeedFilter = .latest
    @Published var searchQuery = ""
    @Published private(set) var solanaHeadlines: [SolanaHeadline] = []
    @Published private(set) var activeHeadlineIndex = 0
    @Published private(set) var popularTopics: [String] = []
    @Published var newsStatusMessage: String?
    @Published private(set) var favoriteMints: Set<String> = []
    @Published private(set) var hiddenMints: Set<String> = []
    @Published private(set) var connectionState: WalletConnectionState = .disconnected
    @Published private(set) var statusMessage: String?
    @Published private(set) var nftCounts: WalletNFTCounts = .zero
    @Published private(set) var nftCount: Int = 0
    @Published private(set) var nftCountLoadState: NFTCountLoadState = .idle
    @Published private(set) var nftDiagnosticsSummary: String?
    @Published private(set) var nftItems: [NFTItem] = []
    @Published var showReminderBanner = false
    @Published var maintenanceMode = false
    @Published var maintenanceMessage = "Service is temporarily unavailable. Please try again in a few minutes."
    @Published private(set) var walletValidationMessage: String?

    private let service: AirdropMonitorService
    private let notificationManager: NotificationManager
    private let walletSession: WalletSessionManager
    private let historyStore: EventHistoryStoring
    private let solanaNewsService: SolanaNewsProviding
    private let analytics: AnalyticsTracking
    private let feedback: FeedbackSubmitting
    private let errorTracker: ErrorTracking
    private let nftCountService: WalletNFTCounting
    private let defaults: UserDefaults

    private let notificationsEnabledKey = "notifications_enabled"
    private let notifyHighRiskOnlyKey = "notify_high_risk_only"
    private let autoScanEnabledKey = "auto_scan_enabled"
    private let favoriteMintsKey = "favorite_mints"
    private let hiddenMintsKey = "hidden_mints"
    private let lastOpenAtKey = "analytics_last_open_at"
    private let reminderDismissedAtKey = "reminder_dismissed_at"
    private var hasTrackedMaintenanceShown = false
    private var syncInFlight = false
    private var refreshAttemptCounter = 0
    private var activeRefreshRequestID = 0
    private var lastRefreshRequestAt: Date = .distantPast
    private var latestRefreshHardFailure = false
    private var lastRefreshTrigger: RefreshTrigger = .manual
    private var didRunOnAppear = false
    private var didRunPostPaintInitialScan = false
    private var scanStatusThrottleTask: Task<Void, Never>?
    private var lastScanStatusEmitAt: Date = .distantPast
    private var scanTask: Task<Void, Never>?
    private var lastScanTaskResult = false
    private var autoScanTask: Task<Void, Never>?
    private var newsRefreshTask: Task<Void, Never>?
    private var newsRotationTask: Task<Void, Never>?

    init(
        service: AirdropMonitorService,
        notificationManager: NotificationManager,
        walletSession: WalletSessionManager,
        historyStore: EventHistoryStoring,
        solanaNewsService: SolanaNewsProviding = GoogleSolanaNewsService(),
        analytics: AnalyticsTracking = BetaAnalyticsService(),
        feedback: FeedbackSubmitting = BetaFeedbackService(),
        errorTracker: ErrorTracking = ErrorTrackerService.shared,
        nftCountService: WalletNFTCounting = NoopWalletNFTCountService(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.notificationManager = notificationManager
        self.walletSession = walletSession
        self.historyStore = historyStore
        self.solanaNewsService = solanaNewsService
        self.analytics = analytics
        self.feedback = feedback
        self.errorTracker = errorTracker
        self.nftCountService = nftCountService
        self.defaults = defaults

        self.notificationsEnabled = defaults.object(forKey: notificationsEnabledKey) as? Bool ?? false
        self.notifyHighRiskOnly = defaults.object(forKey: notifyHighRiskOnlyKey) as? Bool ?? false
        self.autoScanEnabled = defaults.object(forKey: autoScanEnabledKey) as? Bool ?? false
        let favoriteMints = defaults.array(forKey: favoriteMintsKey) as? [String] ?? []
        self.favoriteMints = Set(favoriteMints)
        let hiddenMints = defaults.array(forKey: hiddenMintsKey) as? [String] ?? []
        self.hiddenMints = Set(hiddenMints)
        self.historyEvents = historyStore.load()

        if let connected = walletSession.connectedWallet {
            walletAddress = connected
            connectionState = .connected(connected)
            nftCountLoadState = .idle
            clearRefreshState(resetLastCheckedAt: false)
        }
    }

    deinit {
        scanStatusThrottleTask?.cancel()
        scanTask?.cancel()
        autoScanTask?.cancel()
        newsRefreshTask?.cancel()
        newsRotationTask?.cancel()
    }

    func onAppear() async {
        guard !didRunOnAppear else {
            scanLog("onAppear skipped (already initialized)")
            return
        }
        didRunOnAppear = true

        _ = await checkMaintenanceStatus()
        let now = Date()
        let previousOpen = defaults.object(forKey: lastOpenAtKey) as? Date
        defaults.set(now, forKey: lastOpenAtKey)
        if let previousOpen, now.timeIntervalSince(previousOpen) <= 48 * 60 * 60 {
            Task { await analytics.track(event: "return_visit_48h", properties: [:]) }
        }
        await evaluateReminderEligibility(previousOpen: previousOpen, now: now)
        await notificationManager.refreshAuthorizationStatus()

        if let connected = walletSession.connectedWallet, walletAddress.isEmpty {
            walletAddress = connected
            connectionState = .connected(connected)
        }

        if latestEvents.isEmpty && historyEvents.isEmpty {
            loadDemoData()
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        await refreshSolanaNews()
        startNewsTickerIfNeeded()
        startNewsRefreshLoopIfNeeded()
        startAutoScanIfNeeded()
    }

    func onDisappear() {
        scanStatusThrottleTask?.cancel()
        scanTask?.cancel()
        scanTask = nil
        autoScanTask?.cancel()
        autoScanTask = nil
        newsRefreshTask?.cancel()
        newsRefreshTask = nil
        newsRotationTask?.cancel()
        newsRotationTask = nil
        scanLog("onDisappear: cancelled auto/news timers")
    }

    func persistNotificationPreference() {
        defaults.set(notificationsEnabled, forKey: notificationsEnabledKey)
    }

    func persistHighRiskAlertPreference() {
        defaults.set(notifyHighRiskOnly, forKey: notifyHighRiskOnlyKey)
    }

    func persistAutoScanPreference() {
        defaults.set(autoScanEnabled, forKey: autoScanEnabledKey)
        startAutoScanIfNeeded()
    }

    func connectWallet() {
        let trimmed = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        clearRefreshState(resetLastCheckedAt: true)
        Task { await analytics.track(event: "wallet_connect_start", properties: [:]) }
        guard AddressValidator.isLikelySolanaAddress(trimmed) else {
            walletValidationMessage = "Enter a valid Solana wallet address."
            connectionState = .error("Enter a valid Solana wallet address.")
            statusMessage = "Invalid wallet format."
            return
        }
        walletValidationMessage = nil

        connectionState = .connecting
        walletSession.connect(manualAddress: trimmed)
        if let connected = walletSession.connectedWallet {
            walletAddress = connected
            connectionState = .connected(connected)
            statusMessage = "Wallet connected."
            let walletHash = Self.hashWallet(connected)
            Task {
                await analytics.identify(hashedWallet: walletHash)
                await errorTracker.setUser(hashedWallet: walletHash)
                await analytics.track(event: "wallet_connect_success", properties: [:])
            }
        } else {
            connectionState = .error("Unable to set wallet.")
            statusMessage = "Connection failed."
        }
    }

    func disconnectWallet() {
        walletSession.disconnect()
        walletAddress = ""
        latestEvents = []
        historyEvents = []
        historyStore.clear()
        selectedFilter = .latest
        lastCheckedAt = nil
        errorMessage = nil
        connectionState = .disconnected
        statusMessage = "Wallet disconnected."
        nftCounts = .zero
        nftCount = 0
        nftCountLoadState = .idle
        nftDiagnosticsSummary = nil
        nftItems = []
        clearRefreshState(resetLastCheckedAt: true)
    }

    func clearHistory() {
        historyStore.clear()
        historyEvents = []
    }

    func handleWalletURL(_ url: URL) {
        walletSession.handleDeeplink(url)
        if let connected = walletSession.connectedWallet {
            walletAddress = connected
            connectionState = .connected(connected)
            statusMessage = "Wallet loaded from link."
            nftCountLoadState = .idle
            clearRefreshState(resetLastCheckedAt: false)
        }
    }

    @discardableResult
    func startScan(reason: String) async -> Bool {
        let trimmed = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidator.isLikelySolanaAddress(trimmed) else {
            walletValidationMessage = "Enter a valid Solana wallet address."
            statusMessage = "Paste a valid wallet to begin."
            lastRefreshError = nil
            setScanStatus(.idle, throttle: false)
            scanLog("startScan skipped (invalid wallet) reason=\(reason)")
            return false
        }

        guard scanTask == nil else {
            scanLog("startScan skipped (task in-flight) reason=\(reason)")
            return false
        }

        let trigger: RefreshTrigger
        let silent: Bool
        if reason == "post_paint" {
            guard !didRunPostPaintInitialScan else {
                scanLog("startScan skipped (already ran) reason=\(reason)")
                return false
            }
            didRunPostPaintInitialScan = true
            trigger = .initial
            silent = true
        } else if reason == "auto_scan" {
            trigger = .autoScan
            silent = true
        } else if reason == "retry" {
            trigger = .retry
            silent = false
        } else if reason == "pull_to_refresh" {
            trigger = .pullToRefresh
            silent = false
        } else {
            trigger = .manual
            silent = false
        }

        scanLog("startScan accepted reason=\(reason)")
        scanTask = Task { [weak self] in
            guard let self else { return }
            let ok = await self.refresh(silent: silent, trigger: trigger)
            await MainActor.run {
                self.lastScanTaskResult = ok
                self.scanTask = nil
            }
        }
        if silent {
            // Do not block first paint / background polling on silent scans.
            return true
        }
        await scanTask?.value
        return lastScanTaskResult
    }

    @discardableResult
    func refresh(silent: Bool = false, trigger: RefreshTrigger = .manual) async -> Bool {
        latestRefreshHardFailure = false
        lastRefreshTrigger = trigger
        let now = Date()
        if !silent && now.timeIntervalSince(lastRefreshRequestAt) < 0.8 {
            scanLog("refresh skipped (debounced) trigger=\(trigger.rawValue)")
            return false
        }
        lastRefreshRequestAt = now

        guard !syncInFlight else {
            scanLog("refresh skipped (in-flight) trigger=\(trigger.rawValue)")
            return false
        }
        syncInFlight = true
        isRefreshing = true
        refreshAttemptCounter += 1
        activeRefreshRequestID += 1
        let requestID = activeRefreshRequestID
        scanLog("refresh #\(refreshAttemptCounter) start req=\(requestID) trigger=\(trigger.rawValue) silent=\(silent)")
        var spinnerWatchdog: Task<Void, Never>?
        defer {
            spinnerWatchdog?.cancel()
            syncInFlight = false
            isLoading = false
            isRefreshing = false
            scanLog("refresh req=\(requestID) end")
        }

        let inMaintenance = await checkMaintenanceStatus()
        guard !inMaintenance else {
            statusMessage = "Temporarily unavailable."
            lastRefreshError = "Temporarily unavailable."
            latestRefreshHardFailure = true
            if shouldShowActionableFailure(for: trigger) {
                showActionableScanFailure = true
                passiveScanFailureMessage = nil
                setScanStatus(.failure(lastRefreshError ?? "Temporarily unavailable."))
            } else if trigger == .autoScan, lastCheckedAt != nil {
                showActionableScanFailure = false
                passiveScanFailureMessage = "Monitoring paused"
                scanLog("refresh req=\(requestID) maintenance in background; preserving previous status")
            } else {
                showActionableScanFailure = false
                passiveScanFailureMessage = "Monitoring warming up"
                setScanStatus(.idle)
            }
            return false
        }

        let trimmed = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidator.isLikelySolanaAddress(trimmed) else {
            walletValidationMessage = "Enter a valid Solana wallet address."
            errorMessage = nil
            statusMessage = "Paste a valid wallet to begin."
            // Invalid/empty wallet should not present scan failure banner.
            lastRefreshError = nil
            showActionableScanFailure = false
            passiveScanFailureMessage = nil
            setScanStatus(.idle, throttle: false)
            scanLog("refresh req=\(requestID) blocked: invalid wallet")
            return false
        }
        walletValidationMessage = nil

        walletAddress = trimmed // normalize spacing if user pasted with whitespace
        if case .connected(let connectedAddress) = connectionState, connectedAddress == trimmed {
            // Keep existing connected session.
        } else {
            connectionState = .connecting
            walletSession.connect(manualAddress: trimmed)
            guard let connected = walletSession.connectedWallet, connected == trimmed else {
                connectionState = .error("Unable to connect wallet for scan.")
                errorMessage = "Unable to connect wallet for scan."
                statusMessage = "Connection failed."
                scanLog("refresh req=\(requestID) blocked: wallet connection failed")
                return false
            }
            connectionState = .connected(connected)
        }
        guard case .connected = connectionState else {
            scanLog("refresh req=\(requestID) blocked: wallet state=\(connectionState.debugLabel)")
            return false
        }
        let wasFirstSync = service.isSnapshotMissing(wallet: trimmed)
        let syncStart = Date()
        if !silent {
            isLoading = true
            statusMessage = "Scanning wallet..."
        }
        errorMessage = nil
        lastRefreshError = nil
        showActionableScanFailure = false
        passiveScanFailureMessage = nil
        setScanStatus(.scanning)
        scanLog("refresh req=\(requestID) scanning walletHash=\(Self.hashWallet(trimmed))")

        Task {
            await analytics.track(event: "sync_start", properties: [:])
        }

        if wasFirstSync {
            Task {
                await analytics.track(event: "initial_sync_start", properties: [:])
                await errorTracker.breadcrumb(
                    category: "sync_start",
                    message: "Initial wallet sync started",
                    data: ["walletHash": Self.hashWallet(trimmed)]
                )
            }
        }

        spinnerWatchdog = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if self.isLoading {
                self.isLoading = false
                self.statusMessage = "Sync taking longer than expected. Updating in background."
            }
        }

        do {
            async let newEventsTask = service.checkForAirdrops(wallet: trimmed)
            async let nftSummaryTask = nftCountService.fetchNFTSummary(owner: trimmed)
            nftCountLoadState = .loading
            let newEvents = try await newEventsTask
            guard requestID == activeRefreshRequestID else {
                scanLog("refresh req=\(requestID) ignored (stale result)")
                return false
            }
            latestEvents = newEvents
            historyStore.save(newEvents: newEvents)
            historyEvents = historyStore.load()
            do {
                let summary = try await nftSummaryTask
                applyNFTSummary(summary, wallet: trimmed)
            } catch {
                nftCountLoadState = .failure
                nftDiagnosticsSummary = nil
                await errorTracker.capture(
                    category: "nft_counting_failed",
                    message: error.localizedDescription,
                    httpStatus: nil,
                    extra: ["wallet": trimmed]
                )
            }
            lastCheckedAt = Date()
            errorMessage = nil
            lastRefreshError = nil
            if let checked = lastCheckedAt {
                setScanStatus(.success(checked))
            }
            connectionState = .connected(trimmed)
            let completionStatus = await Task.detached(priority: .utility) {
                newEvents.isEmpty
                    ? "No airdrops detected."
                    : "Scan complete: \(newEvents.count) events."
            }.value
            statusMessage = completionStatus
            if wasFirstSync {
                statusMessage = "Baseline snapshot created. Next refresh compares deltas."
            }
            scanLog("refresh req=\(requestID) success tokens=\(newEvents.count) nfts=\(nftCounts.total)")

            if notificationsEnabled {
                let eventsForAlert = notifyHighRiskOnly
                    ? newEvents.filter { $0.risk.level == .high }
                    : newEvents
                await notificationManager.notifyNewAirdrops(eventsForAlert)
            }
            Task {
                let durationMs = String(Int(Date().timeIntervalSince(syncStart) * 1000))
                await analytics.track(
                    event: "sync_success",
                    properties: ["sync_ms": durationMs]
                )
            }
            if wasFirstSync {
                Task {
                    let durationMs = String(Int(Date().timeIntervalSince(syncStart) * 1000))
                    await analytics.track(
                        event: "initial_sync_success",
                        properties: [
                            "eventCount": String(newEvents.count),
                            "sync_duration_ms": durationMs
                        ]
                    )
                    await errorTracker.breadcrumb(
                        category: "sync_success",
                        message: "Initial wallet sync completed",
                        data: ["eventCount": String(newEvents.count)]
                    )
                }
            }

            return true
        } catch {
            guard requestID == activeRefreshRequestID else {
                scanLog("refresh req=\(requestID) ignored error (stale): \(error.localizedDescription)")
                return false
            }
            latestRefreshHardFailure = true
            errorMessage = error.localizedDescription
            connectionState = .error(error.localizedDescription)
            statusMessage = "Scan failed."
            lastRefreshError = error.localizedDescription
            if shouldShowActionableFailure(for: trigger) {
                showActionableScanFailure = true
                passiveScanFailureMessage = nil
                setScanStatus(.failure(lastRefreshError ?? "Refresh failed."))
            } else if trigger == .autoScan, lastCheckedAt != nil {
                showActionableScanFailure = false
                passiveScanFailureMessage = "Monitoring paused"
                scanLog("refresh req=\(requestID) auto-scan failed; preserving previous scan status")
            } else {
                showActionableScanFailure = false
                passiveScanFailureMessage = "Monitoring warming up"
                setScanStatus(.idle)
            }
            scanLog("refresh req=\(requestID) failed: \(error.localizedDescription)")
            let errorMeta = Self.categorizeError(error)
            await errorTracker.capture(
                category: errorMeta.category,
                message: error.localizedDescription,
                httpStatus: errorMeta.httpStatus,
                extra: ["flow": "wallet_sync"]
            )
            Task {
                let durationMs = String(Int(Date().timeIntervalSince(syncStart) * 1000))
                await analytics.track(
                    event: "sync_fail",
                    properties: [
                        "error": errorMeta.category,
                        "httpStatus": errorMeta.httpStatus.map(String.init) ?? "unknown",
                        "sync_ms": durationMs
                    ]
                )
            }
            if wasFirstSync {
                Task {
                    let durationMs = String(Int(Date().timeIntervalSince(syncStart) * 1000))
                    await analytics.track(
                        event: "initial_sync_fail",
                        properties: [
                            "error_category": errorMeta.category,
                            "http_status": errorMeta.httpStatus.map(String.init) ?? "unknown",
                            "sync_duration_ms": durationMs
                        ]
                    )
                    await errorTracker.breadcrumb(
                        category: "sync_fail",
                        message: "Initial wallet sync failed",
                        data: [
                            "errorCategory": errorMeta.category,
                            "httpStatus": errorMeta.httpStatus.map(String.init) ?? "unknown"
                        ]
                    )
                }
            }
            if nftCountLoadState == .loading {
                nftCountLoadState = .failure
            }
            return false
        }
    }

    func refreshNFTCountsOnly() async {
        let trimmed = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidator.isLikelySolanaAddress(trimmed) else {
            nftCountLoadState = .failure
            nftDiagnosticsSummary = nil
            return
        }

        nftCountLoadState = .loading
        do {
            let summary = try await nftCountService.fetchNFTSummary(owner: trimmed)
            applyNFTSummary(summary, wallet: trimmed)
        } catch {
            nftCountLoadState = .failure
            nftDiagnosticsSummary = nil
            await errorTracker.capture(
                category: "nft_counting_failed",
                message: error.localizedDescription,
                httpStatus: nil,
                extra: ["wallet": trimmed, "flow": "nft_only_retry"]
            )
        }
    }

    private func applyNFTSummary(_ summary: NFTSummary, wallet: String) {
        let counts = WalletNFTCounts(
            standardNFTCount: summary.uncompressedCount,
            compressedNFTCount: summary.compressedCount
        )
        nftCounts = counts
        nftCount = summary.totalCount
        nftDiagnosticsSummary = NFTCountDiagnostics(
            candidates: summary.debug.candidates,
            metadataFound: summary.debug.metadataFound,
            editionsFound: summary.debug.editionsFound,
            compressedFound: summary.debug.compressedFound
        ).summary + " via \(summary.dataSource.rawValue)"
        nftCountLoadState = .success
        Task { [weak self] in
            guard let self else { return }
            let items = await self.nftCountService.fetchNFTItems(owner: wallet)
            self.nftItems = items
        }
    }

    private func clearRefreshState(resetLastCheckedAt: Bool) {
        lastRefreshError = nil
        showActionableScanFailure = false
        passiveScanFailureMessage = nil
        setScanStatus(.idle, throttle: false)
        errorMessage = nil
        if resetLastCheckedAt {
            lastCheckedAt = nil
        }
    }

    func trackPullToRefresh() {
        Task {
            await analytics.track(event: "pull_to_refresh", properties: [:])
        }
    }

    func trackAlertsTabOpen() {
        Task {
            await analytics.track(event: "alerts_open", properties: [:])
            await analytics.track(event: "alerts_tab_open", properties: [:])
            await errorTracker.breadcrumb(category: "alerts_open", message: "Alerts tab opened", data: [:])
        }
    }

    func trackActivityTabOpen() {
        Task {
            await analytics.track(event: "activity_open", properties: [:])
            await analytics.track(event: "activity_tab_open", properties: [:])
        }
    }

    func trackAlertOpen(alertType: String) {
        Task {
            await analytics.track(
                event: "alert_open",
                properties: [
                    "type": alertType,
                    "alert_type": alertType
                ]
            )
        }
    }

    func trackClaimOpen(claimType: String) {
        Task {
            await analytics.track(event: "claim_open", properties: ["claim_type": claimType])
            await errorTracker.breadcrumb(category: "claim_open", message: "Claim opened", data: ["claim_type": claimType])
        }
    }

    func trackFeedbackOpen() {
        Task {
            await analytics.track(event: "feedback_open", properties: [:])
        }
    }

    func trackEnvironmentMismatch(environment: String, baseURL: String) {
        Task {
            await analytics.track(
                event: "env_mismatch_detected",
                properties: [
                    "environment": environment,
                    "base_url": baseURL
                ]
            )
        }
    }

    func trackDiagnosticsOpened() {
        Task {
            await analytics.track(event: "diagnostics_opened", properties: [:])
        }
    }

    func trackPreflightRan() {
        Task {
            await analytics.track(event: "preflight_ran", properties: [:])
        }
    }

    func trackPreflightFailed(reason: String) {
        Task {
            await analytics.track(
                event: "preflight_failed",
                properties: ["reason": reason]
            )
        }
    }

    func retryMaintenanceCheck() async {
        _ = await checkMaintenanceStatus()
    }

    func diagnosticsSendTestAnalyticsEvent(env: String, baseURL: String) async {
        await analytics.track(
            event: "test_event",
            properties: [
                "event_name": "test_event",
                "env": env,
                "baseUrl": baseURL
            ]
        )
    }

    func diagnosticsSendTestFeedback() async -> Bool {
        let walletHash = Self.hashWallet(walletAddress.trimmingCharacters(in: .whitespacesAndNewlines))
        return await feedback.send(
            message: "TestFlight feedback test",
            hashedWallet: walletHash,
            screenshotBase64: nil
        )
    }

    func diagnosticsSendTestNonFatalError() async {
        await errorTracker.capture(
            category: "testflight_non_fatal",
            message: "TestFlight non-fatal test",
            httpStatus: nil,
            extra: ["source": "diagnostics", "type": "captureMessage"]
        )
    }

    var diagnosticsHashedWalletPresent: Bool {
        Self.hashWallet(walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)) != "none"
    }

    var isMaintenanceMode: Bool {
        maintenanceMode
    }

    func trackOnboardingViewed() {
        Task {
            await analytics.track(event: "onboarding_viewed", properties: [:])
        }
    }

    func trackOnboardingDismissed() {
        Task {
            await analytics.track(event: "onboarding_dismissed", properties: [:])
        }
    }

    func trackOnboardingFeedbackTapped() {
        Task {
            await analytics.track(event: "onboarding_feedback_tapped", properties: [:])
        }
    }

    func dismissReminderBanner() {
        showReminderBanner = false
        defaults.set(Date(), forKey: reminderDismissedAtKey)
        Task {
            await analytics.track(event: "reminder_dismissed", properties: [:])
        }
    }

    func reminderFeedbackTapped() {
        showReminderBanner = false
        defaults.set(Date(), forKey: reminderDismissedAtKey)
        Task {
            await analytics.track(event: "reminder_feedback_tapped", properties: [:])
        }
    }

    func submitFeedback(message: String, screenshotBase64: String?) async -> Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let walletHash = Self.hashWallet(walletAddress.trimmingCharacters(in: .whitespacesAndNewlines))
        let ok = await feedback.send(message: trimmed, hashedWallet: walletHash, screenshotBase64: screenshotBase64)
        await analytics.track(
            event: ok ? "feedback_sent" : "feedback_failed",
            properties: [
                "hashed_wallet": walletHash
            ]
        )
        return ok
    }

    var displayedEvents: [AirdropEvent] {
        let source: [AirdropEvent]
        switch selectedFilter {
        case .latest:
            source = latestEvents
        case .history:
            source = historyEvents
        case .highRisk:
            source = historyEvents.filter { $0.risk.level == .high }
        case .watchlist:
            source = historyEvents.filter { favoriteMints.contains($0.mint) }
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let visibleSource = source.filter { !hiddenMints.contains($0.mint) }
            .sorted(by: eventSort)
        guard !query.isEmpty else { return visibleSource }

        return visibleSource.filter {
            $0.metadata.name.lowercased().contains(query) ||
            $0.metadata.symbol.lowercased().contains(query) ||
            $0.mint.lowercased().contains(query)
        }
    }

    var highRiskCount: Int {
        historyEvents.filter { $0.risk.level == .high }.count
    }

    var totalDetectedCount: Int {
        historyEvents.count
    }

    var watchlistCount: Int {
        historyEvents.filter { favoriteMints.contains($0.mint) && !hiddenMints.contains($0.mint) }.count
    }

    var mediumRiskCount: Int {
        historyEvents.filter { $0.risk.level == .medium }.count
    }

    var lowRiskCount: Int {
        historyEvents.filter { $0.risk.level == .low }.count
    }

    var latestDetectedAmount: Decimal {
        latestEvents.reduce(0) { $0 + $1.delta }
    }

    var totalDetectedAmount: Decimal {
        historyEvents.reduce(0) { $0 + $1.delta }
    }

    var currentHeadline: SolanaHeadline? {
        guard !solanaHeadlines.isEmpty else { return nil }
        let index = min(activeHeadlineIndex, solanaHeadlines.count - 1)
        return solanaHeadlines[index]
    }

    var hasWalletAddress: Bool {
        !walletAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isWalletAddressValid: Bool {
        let trimmed = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        return AddressValidator.isLikelySolanaAddress(trimmed)
    }

    var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    var shouldShowWalletOnboarding: Bool {
        !hasWalletAddress || !isWalletAddressValid || !isConnected
    }

    var hasValidWalletAddress: Bool {
        isWalletAddressValid
    }

    var hiddenTokenCount: Int {
        hiddenMints.count
    }

    var totalNFTCount: Int {
        nftCount
    }

    var dataFreshnessText: String {
        guard let lastCheckedAt else { return "Connect wallet to load data." }
        return "Last Updated: \(lastCheckedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    var freshnessWarning: String? {
        guard let lastCheckedAt else { return nil }
        let age = Date().timeIntervalSince(lastCheckedAt)
        return age > 6 * 60 * 60 ? "Data may be outdated. Pull to refresh." : nil
    }

    var dataConfidenceLabel: String {
        guard let lastCheckedAt else { return "" }
        let age = Date().timeIntervalSince(lastCheckedAt)
        if age <= 30 * 60 { return "High confidence data" }
        if age <= 6 * 60 * 60 { return "Partial data" }
        return "Delayed sync"
    }

    var securityScore: Int {
        var score = 34
        if hasValidWalletAddress { score += 20 }
        if notificationsEnabled { score += 14 }
        if notifyHighRiskOnly { score += 10 }
        if autoScanEnabled { score += 10 }
        if hiddenTokenCount > 0 { score += 8 }
        return min(score, 100)
    }

    var integrityTopFactors: [String] {
        var factors: [String] = []
        factors.append(hasValidWalletAddress ? "Wallet format checks pass (+20)." : "No valid wallet connected yet.")
        factors.append(notificationsEnabled ? "Alert channel enabled (+14)." : "Alert channel disabled.")
        factors.append(notifyHighRiskOnly ? "High-risk notification filter active (+10)." : "All-risk notification mode enabled.")
        factors.append(autoScanEnabled ? "Background scanning active (+10)." : "Background scanning disabled.")
        return Array(factors.prefix(3))
    }

    func loadDemoData() {
        let now = Date()
        let demo: [AirdropEvent] = [
            AirdropEvent(
                wallet: walletAddress.isEmpty ? "DemoWallet1111111111111111111111111111111111" : walletAddress,
                mint: "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN",
                oldAmount: 0,
                newAmount: 24.5,
                metadata: TokenMetadata(
                    mint: "JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN",
                    symbol: "JUP",
                    name: "Jupiter",
                    logoURL: nil
                ),
                risk: ClaimRiskAssessment(level: .low, score: 10, reasons: ["Known token metadata and healthy transfer size."]),
                detectedAt: now
            ),
            AirdropEvent(
                wallet: walletAddress.isEmpty ? "DemoWallet1111111111111111111111111111111111" : walletAddress,
                mint: "Fre3ClaimB0nus111111111111111111111111111111",
                oldAmount: 0,
                newAmount: 0.0001,
                metadata: TokenMetadata(
                    mint: "Fre3ClaimB0nus111111111111111111111111111111",
                    symbol: "FREECLAIM",
                    name: "Free Claim Bonus",
                    logoURL: nil
                ),
                risk: ClaimRiskAssessment(
                    level: .high,
                    score: 88,
                    reasons: [
                        "Token name/symbol contains common scam keywords.",
                        "Tiny balance increase; dust airdrops can be phishing bait."
                    ]
                ),
                detectedAt: now.addingTimeInterval(-320)
            )
        ]

        latestEvents = demo
        historyStore.save(newEvents: demo)
        historyEvents = historyStore.load()
        selectedFilter = .latest
        lastCheckedAt = now
        errorMessage = nil
        if let connected = walletSession.connectedWallet {
            connectionState = .connected(connected)
        } else if AddressValidator.isLikelySolanaAddress(walletAddress) {
            connectionState = .connected(walletAddress)
        }
        statusMessage = "Demo results loaded."
    }

    func refreshSolanaNews() async {
        do {
            let headlines = try await solanaNewsService.fetchLatest()
            solanaHeadlines = headlines
            popularTopics = extractPopularTopics(from: headlines)
            if activeHeadlineIndex >= headlines.count {
                activeHeadlineIndex = 0
            }
            newsStatusMessage = headlines.isEmpty ? "No live Solana headlines right now." : nil
            startNewsTickerIfNeeded()
        } catch {
            newsStatusMessage = "Could not load live Solana headlines."
        }
    }

    func isFavorite(mint: String) -> Bool {
        favoriteMints.contains(mint)
    }

    func toggleFavorite(mint: String) {
        if favoriteMints.contains(mint) {
            favoriteMints.remove(mint)
        } else {
            favoriteMints.insert(mint)
        }
        persistFavorites()
    }

    func hideMint(_ mint: String) {
        hiddenMints.insert(mint)
        persistHiddenMints()
    }

    func unhideAllMints() {
        hiddenMints = Set<String>()
        persistHiddenMints()
    }

    private func persistFavorites() {
        defaults.set(Array(favoriteMints).sorted(), forKey: favoriteMintsKey)
    }

    private func persistHiddenMints() {
        defaults.set(Array(hiddenMints).sorted(), forKey: hiddenMintsKey)
    }

    private func eventSort(lhs: AirdropEvent, rhs: AirdropEvent) -> Bool {
        let leftFavorite = favoriteMints.contains(lhs.mint)
        let rightFavorite = favoriteMints.contains(rhs.mint)
        if leftFavorite != rightFavorite {
            return leftFavorite && !rightFavorite
        }
        return lhs.detectedAt > rhs.detectedAt
    }

    private func startAutoScanIfNeeded() {
        autoScanTask?.cancel()
        autoScanTask = nil

        guard autoScanEnabled else {
            scanLog("auto-scan disabled")
            return
        }
        scanLog("auto-scan enabled")

        autoScanTask = Task { [weak self] in
            var backoffSeconds: UInt64 = 600
            var consecutiveFailures = 0
            let maxConsecutiveFailures = 3
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
                } catch {
                    break
                }

                guard let self else { break }
                guard AddressValidator.isLikelySolanaAddress(self.walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    await MainActor.run {
                        self.scanLog("auto-scan skipped (invalid wallet)")
                        self.statusMessage = "Paste a valid wallet to begin."
                    }
                    continue
                }

                let ok = await self.startScan(reason: "auto_scan")
                await MainActor.run {
                    if ok {
                        backoffSeconds = 600
                        consecutiveFailures = 0
                        self.scanLog("auto-scan success; next interval=600s")
                    } else if self.latestRefreshHardFailure {
                        consecutiveFailures += 1
                        backoffSeconds = min(backoffSeconds * 2, 3_600)
                        self.scanLog("auto-scan hard failure #\(consecutiveFailures); backoff interval=\(backoffSeconds)s")
                        if consecutiveFailures >= maxConsecutiveFailures {
                            self.scanLog("auto-scan paused after \(consecutiveFailures) consecutive failures")
                            self.statusMessage = "Auto-scan paused after repeated failures. Tap Refresh to retry."
                        }
                    } else {
                        backoffSeconds = 600
                        self.scanLog("auto-scan skipped/no-op; next interval=600s")
                    }
                }
                if consecutiveFailures >= maxConsecutiveFailures {
                    break
                }
            }
        }
    }

    private func setScanStatus(_ newValue: ScanStatus, throttle: Bool = true) {
        let minimumUpdateInterval: TimeInterval = 0.25
        if !throttle {
            scanStatusThrottleTask?.cancel()
            scanStatus = newValue
            lastScanStatusEmitAt = Date()
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastScanStatusEmitAt)
        if elapsed >= minimumUpdateInterval {
            scanStatusThrottleTask?.cancel()
            scanStatus = newValue
            lastScanStatusEmitAt = now
            return
        }

        let delay = max(0, minimumUpdateInterval - elapsed)
        scanStatusThrottleTask?.cancel()
        scanStatusThrottleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.scanStatus = newValue
                self.lastScanStatusEmitAt = Date()
            }
        }
    }

    private func shouldShowActionableFailure(for trigger: RefreshTrigger) -> Bool {
        switch trigger {
        case .manual, .pullToRefresh, .retry:
            return true
        case .autoScan, .initial:
            return false
        }
    }

    private func scanLog(_ message: String) {
#if DEBUG
        print("[ScanDebug] \(Date().timeIntervalSince1970) \(message)")
#endif
    }

    private func startNewsRefreshLoopIfNeeded() {
        newsRefreshTask?.cancel()
        newsRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 900_000_000_000)
                } catch {
                    break
                }
                guard let self else { break }
                await self.refreshSolanaNews()
            }
        }
    }

    private func startNewsTickerIfNeeded() {
        newsRotationTask?.cancel()
        newsRotationTask = nil

        guard solanaHeadlines.count > 1 else { return }

        newsRotationTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    break
                }

                guard let self else { break }
                guard !self.solanaHeadlines.isEmpty else { continue }
                self.activeHeadlineIndex = (self.activeHeadlineIndex + 1) % self.solanaHeadlines.count
            }
        }
    }

    private func extractPopularTopics(from headlines: [SolanaHeadline]) -> [String] {
        let blocked = Set([
            "solana", "crypto", "cryptocurrency", "price", "token", "tokens", "coin", "coins",
            "market", "markets", "today", "news", "latest", "surges", "rally", "update",
            "after", "with", "from", "into", "amid", "this", "that", "over", "under",
            "hits", "will", "could", "about", "your", "you", "are", "the", "and", "for"
        ])

        var counts: [String: Int] = [:]
        for headline in headlines {
            let words = headline.title.lowercased()
                .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
                .split(separator: " ")
                .map(String.init)
            for word in words where word.count >= 4 && !blocked.contains(word) {
                counts[word, default: 0] += 1
            }
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .prefix(7)
            .map { $0.key.capitalized }
    }

    private func evaluateReminderEligibility(previousOpen: Date?, now: Date) async {
        guard walletSession.connectedWallet != nil else {
            showReminderBanner = false
            return
        }
        guard let previousOpen else {
            showReminderBanner = false
            return
        }

        let inactivity = now.timeIntervalSince(previousOpen)
        guard inactivity > 48 * 60 * 60 else {
            showReminderBanner = false
            return
        }

        let dismissedAt = defaults.object(forKey: reminderDismissedAtKey) as? Date
        if let dismissedAt, dismissedAt > previousOpen {
            showReminderBanner = false
            return
        }

        showReminderBanner = true
        await analytics.track(event: "reminder_shown_48h", properties: [:])
    }

    private func checkMaintenanceStatus() async -> Bool {
        guard let base = AppEnvironment.current.apiBaseURL,
              let endpoint = URL(string: "/v1/meta", relativeTo: base) else {
            return false
        }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return maintenanceMode
            }
            let meta = try await Task.detached(priority: .utility) {
                try JSONDecoder().decode(MaintenanceMetaResponse.self, from: data)
            }.value
            maintenanceMode = meta.maintenanceMode
            if let message = meta.maintenanceMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                maintenanceMessage = message
            }

            if maintenanceMode && !hasTrackedMaintenanceShown {
                hasTrackedMaintenanceShown = true
                await analytics.track(event: "maintenance_shown", properties: [:])
            }
            if !maintenanceMode {
                hasTrackedMaintenanceShown = false
            }
            return maintenanceMode
        } catch {
            return maintenanceMode
        }
    }

    private static func hashWallet(_ wallet: String) -> String {
        let trimmed = wallet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "none" }
        let digest = SHA256.hash(data: Data(trimmed.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(12))
    }

    private static func categorizeError(_ error: Error) -> (category: String, httpStatus: Int?) {
        if let rpc = error as? SolanaRPCError {
            switch rpc {
            case .timeout:
                return ("network_timeout", nil)
            case .invalidResponse:
                return ("api_non_200", nil)
            case .rpcError(let msg):
                return ("sync_pipeline_failure", Int(msg.filter(\.isNumber)))
            case .unsupported:
                return ("sync_pipeline_failure", nil)
            }
        }
        if let urlError = error as? URLError {
            if urlError.code == .timedOut { return ("network_timeout", nil) }
            return ("network_error", nil)
        }
        if error is DecodingError {
            return ("decoding_error", nil)
        }
        return ("sync_pipeline_failure", nil)
    }
}

private struct MaintenanceMetaResponse: Decodable {
    let maintenanceMode: Bool
    let maintenanceMessage: String?
}

struct SolanaHeadline: Identifiable, Equatable {
    let title: String
    let source: String
    let publishedAt: Date?
    let url: URL

    var id: String { url.absoluteString }
}

protocol SolanaNewsProviding {
    func fetchLatest() async throws -> [SolanaHeadline]
}

enum SolanaNewsError: LocalizedError {
    case invalidResponse
    case parseFailed
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid news response."
        case .parseFailed:
            return "Could not parse news feed."
        case .timeout:
            return "News request timed out."
        }
    }
}

final class GoogleSolanaNewsService: SolanaNewsProviding {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchLatest() async throws -> [SolanaHeadline] {
        guard let url = URL(string: "https://news.google.com/rss/search?q=solana&hl=en-US&gl=US&ceid=US:en") else {
            throw SolanaNewsError.invalidResponse
        }
        let (data, response) = try await requestWithRetry(url: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SolanaNewsError.invalidResponse
        }

        let parser = SolanaRSSParser()
        let items = parser.parse(data: data)
        let filtered = items.filter { item in
            let haystack = "\(item.title) \(item.source)".lowercased()
            return haystack.contains("solana")
        }
        return Array(filtered.prefix(25))
    }

    private func requestWithRetry(url: URL, maxAttempts: Int = 3) async throws -> (Data, URLResponse) {
        var attempt = 0
        var delayNs: UInt64 = 350_000_000
        var lastError: Error = SolanaNewsError.invalidResponse
        while attempt < maxAttempts {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                return try await session.data(for: request)
            } catch {
                lastError = error
                attempt += 1
                if attempt >= maxAttempts { break }
                try? await Task.sleep(nanoseconds: delayNs)
                delayNs = min(delayNs * 2, 2_000_000_000)
            }
        }
        if let urlError = lastError as? URLError, urlError.code == .timedOut {
            throw SolanaNewsError.timeout
        }
        throw lastError
    }
}

private final class SolanaRSSParser: NSObject, XMLParserDelegate {
    private struct Entry {
        var title = ""
        var link = ""
        var source = ""
        var pubDate = ""
    }

    private var entries: [Entry] = []
    private var currentEntry: Entry?
    private var currentElement = ""
    private var currentText = ""

    func parse(data: Data) -> [SolanaHeadline] {
        entries = []
        currentEntry = nil
        currentElement = ""
        currentText = ""

        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { return [] }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "E, d MMM yyyy HH:mm:ss Z"

        return entries.compactMap { entry in
            guard let url = URL(string: entry.link), !entry.title.isEmpty else {
                return nil
            }
            let inferredSource = inferSource(title: entry.title, explicit: entry.source)
            return SolanaHeadline(
                title: sanitizeTitle(entry.title),
                source: inferredSource,
                publishedAt: dateFormatter.date(from: entry.pubDate),
                url: url
            )
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "item" {
            currentEntry = Entry()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var currentEntry else { return }

        switch elementName {
        case "title":
            currentEntry.title = text
        case "link":
            currentEntry.link = text
        case "source":
            currentEntry.source = text
        case "pubDate":
            currentEntry.pubDate = text
        case "item":
            entries.append(currentEntry)
            self.currentEntry = nil
            return
        default:
            break
        }
        self.currentEntry = currentEntry
    }

    private func inferSource(title: String, explicit: String) -> String {
        if !explicit.isEmpty {
            return explicit
        }
        let parts = title.components(separatedBy: " - ")
        if parts.count > 1, let last = parts.last, !last.isEmpty {
            return last
        }
        return "Source"
    }

    private func sanitizeTitle(_ title: String) -> String {
        let parts = title.components(separatedBy: " - ")
        if parts.count > 1 {
            return parts.dropLast().joined(separator: " - ")
        }
        return title
    }
}

private struct NoopWalletNFTCountService: WalletNFTCounting {
    func fetchNFTSummary(owner: String) async throws -> NFTSummary {
        .zero
    }

    func fetchCounts(wallet: String) async throws -> WalletNFTCounts {
        .zero
    }

    func fetchDetailedCounts(wallet: String) async throws -> NFTCountFetchResult {
        NFTCountFetchResult(counts: .zero, diagnostics: .zero)
    }
}
