import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var walletAddress = ""
    @Published var latestEvents: [AirdropEvent] = []
    @Published var historyEvents: [AirdropEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastCheckedAt: Date?
    @Published var notificationsEnabled = true
    @Published var autoScanEnabled = false
    @Published var selectedFilter: EventFeedFilter = .latest
    @Published var searchQuery = ""

    private let service: AirdropMonitorService
    private let notificationManager: NotificationManager
    private let walletSession: WalletSessionManager
    private let historyStore: EventHistoryStoring
    private let defaults: UserDefaults

    private let notificationsEnabledKey = "notifications_enabled"
    private let autoScanEnabledKey = "auto_scan_enabled"
    private var autoScanTask: Task<Void, Never>?

    init(
        service: AirdropMonitorService,
        notificationManager: NotificationManager,
        walletSession: WalletSessionManager,
        historyStore: EventHistoryStoring,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.notificationManager = notificationManager
        self.walletSession = walletSession
        self.historyStore = historyStore
        self.defaults = defaults

        self.notificationsEnabled = defaults.object(forKey: notificationsEnabledKey) as? Bool ?? true
        self.autoScanEnabled = defaults.object(forKey: autoScanEnabledKey) as? Bool ?? false
        self.historyEvents = historyStore.load()

        if let connected = walletSession.connectedWallet {
            walletAddress = connected
        }
    }

    deinit {
        autoScanTask?.cancel()
    }

    func onAppear() async {
        await notificationManager.refreshAuthorizationStatus()

        if let connected = walletSession.connectedWallet, walletAddress.isEmpty {
            walletAddress = connected
        }

        historyEvents = historyStore.load()
        startAutoScanIfNeeded()
    }

    func onDisappear() {
        autoScanTask?.cancel()
        autoScanTask = nil
    }

    func persistNotificationPreference() {
        defaults.set(notificationsEnabled, forKey: notificationsEnabledKey)
    }

    func persistAutoScanPreference() {
        defaults.set(autoScanEnabled, forKey: autoScanEnabledKey)
        startAutoScanIfNeeded()
    }

    func connectWallet() {
        walletSession.connect(manualAddress: walletAddress)
        if let connected = walletSession.connectedWallet {
            walletAddress = connected
        }
    }

    func disconnectWallet() {
        walletSession.disconnect()
        walletAddress = ""
        latestEvents = []
        errorMessage = nil
    }

    func clearHistory() {
        historyStore.clear()
        historyEvents = []
    }

    func handleWalletURL(_ url: URL) {
        walletSession.handleDeeplink(url)
        if let connected = walletSession.connectedWallet {
            walletAddress = connected
        }
    }

    func refresh() async {
        let trimmed = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidator.isLikelySolanaAddress(trimmed) else {
            errorMessage = "Enter a valid Solana wallet address."
            return
        }

        walletAddress = trimmed
        connectWallet()
        isLoading = true
        errorMessage = nil

        do {
            let newEvents = try await service.checkForAirdrops(wallet: trimmed)
            latestEvents = newEvents
            historyStore.save(newEvents: newEvents)
            historyEvents = historyStore.load()
            lastCheckedAt = Date()

            if notificationsEnabled {
                await notificationManager.notifyNewAirdrops(newEvents)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return source }

        return source.filter {
            $0.metadata.name.lowercased().contains(query) ||
            $0.metadata.symbol.lowercased().contains(query) ||
            $0.mint.lowercased().contains(query)
        }
    }

    var highRiskCount: Int {
        historyEvents.filter { $0.risk.level == .high }.count
    }

    private func startAutoScanIfNeeded() {
        autoScanTask?.cancel()
        autoScanTask = nil

        guard autoScanEnabled else { return }

        autoScanTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 600_000_000_000)
                } catch {
                    break
                }

                guard let self else { break }
                if !self.walletAddress.isEmpty {
                    await self.refresh()
                }
            }
        }
    }
}
