import SwiftUI

@main
struct AirdropCheckerApp: App {
    private let walletSession = WalletSessionManager()
    private let notificationManager = NotificationManager()

    var body: some Scene {
        WindowGroup {
            ContentView(
                viewModel: DashboardViewModel(
                    service: AirdropMonitorService(
                        rpcClient: SolanaRPCClient(),
                        metadataService: TokenMetadataService(),
                        riskScoring: ClaimRiskScoringService()
                    ),
                    notificationManager: notificationManager,
                    walletSession: walletSession
                )
            )
        }
    }
}
