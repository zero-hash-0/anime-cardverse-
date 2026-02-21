import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var walletAddress = ""
    @Published var events: [AirdropEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastCheckedAt: Date?
    @Published var notificationsEnabled = true

    private let service: AirdropMonitorService
    private let notificationManager: NotificationManager
    private let walletSession: WalletSessionManager
    private let defaults: UserDefaults
    private let notificationsEnabledKey = "notifications_enabled"

    init(
        service: AirdropMonitorService,
        notificationManager: NotificationManager,
        walletSession: WalletSessionManager,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.notificationManager = notificationManager
        self.walletSession = walletSession
        self.defaults = defaults
        self.notificationsEnabled = defaults.object(forKey: notificationsEnabledKey) as? Bool ?? true

        if let connected = walletSession.connectedWallet {
            walletAddress = connected
        }
    }

    func onAppear() async {
        await notificationManager.refreshAuthorizationStatus()

        if let connected = walletSession.connectedWallet, walletAddress.isEmpty {
            walletAddress = connected
        }
    }

    func persistNotificationPreference() {
        defaults.set(notificationsEnabled, forKey: notificationsEnabledKey)
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
        events = []
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
            events = newEvents
            lastCheckedAt = Date()

            if notificationsEnabled {
                await notificationManager.notifyNewAirdrops(newEvents)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
