import Foundation

@MainActor
final class WalletSessionManager: ObservableObject {
    @Published private(set) var connectedWallet: String?

    private let defaults: UserDefaults
    private let walletKey = "connected_wallet"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        connectedWallet = defaults.string(forKey: walletKey)
    }

    func connect(manualAddress: String) {
        let trimmed = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AddressValidator.isLikelySolanaAddress(trimmed) else { return }

        connectedWallet = trimmed
        defaults.set(trimmed, forKey: walletKey)
    }

    func disconnect() {
        connectedWallet = nil
        defaults.removeObject(forKey: walletKey)
    }

    func handleDeeplink(_ url: URL) {
        guard url.scheme?.lowercased() == "airdropchecker" else { return }
        guard url.host?.lowercased() == "wallet" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let value = components?.queryItems?.first(where: { $0.name == "address" })?.value else {
            return
        }

        connect(manualAddress: value)
    }
}
