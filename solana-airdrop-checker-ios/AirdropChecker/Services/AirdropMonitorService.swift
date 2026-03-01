import Foundation

final class AirdropMonitorService {
    private let rpcClient: SolanaRPCFetching
    private let metadataService: TokenMetadataProviding
    private let riskScoring: ClaimRiskScoring
    private let defaults: UserDefaults
    private let snapshotKeyPrefix = "wallet_snapshot_"
    private let snapshotUpdatedAtKeyPrefix = "wallet_snapshot_updated_at_"

    init(
        rpcClient: SolanaRPCFetching,
        metadataService: TokenMetadataProviding,
        riskScoring: ClaimRiskScoring,
        defaults: UserDefaults = .standard
    ) {
        self.rpcClient = rpcClient
        self.metadataService = metadataService
        self.riskScoring = riskScoring
        self.defaults = defaults
    }

    func checkForAirdrops(wallet: String) async throws -> [AirdropEvent] {
        let current = try await rpcClient.fetchTokenBalances(owner: wallet)
        let previous = loadSnapshot(wallet: wallet)

        let increases: [(token: TokenBalance, oldAmount: Decimal)] = await Task.detached(priority: .utility) {
            var previousByMint: [String: Decimal] = [:]
            for token in previous where previousByMint[token.mint] == nil {
                previousByMint[token.mint] = token.amount
            }
            var output: [(token: TokenBalance, oldAmount: Decimal)] = []
            output.reserveCapacity(current.count)
            for token in current {
                let oldAmount = previousByMint[token.mint] ?? 0
                if token.amount > oldAmount {
                    output.append((token, oldAmount))
                }
            }
            return output
        }.value

        var events: [AirdropEvent] = []
        events.reserveCapacity(increases.count)

        for increase in increases {
            let token = increase.token
            let oldAmount = increase.oldAmount

            let metadata = await metadataService.metadata(for: token.mint)
            let risk = riskScoring.evaluate(eventDelta: token.amount - oldAmount, metadata: metadata)

            events.append(AirdropEvent(
                wallet: wallet,
                mint: token.mint,
                oldAmount: oldAmount,
                newAmount: token.amount,
                metadata: metadata,
                risk: risk,
                detectedAt: Date()
            ))
        }

        saveSnapshot(current, wallet: wallet)
        return events.sorted { $0.delta > $1.delta }
    }

    func isSnapshotMissing(wallet: String) -> Bool {
        loadSnapshot(wallet: wallet).isEmpty
    }

    func cachedSnapshotUpdatedAt(wallet: String) -> Date? {
        defaults.object(forKey: snapshotUpdatedAtKeyPrefix + wallet) as? Date
    }

    private func saveSnapshot(_ snapshot: [TokenBalance], wallet: String) {
        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(encoded, forKey: snapshotKeyPrefix + wallet)
        defaults.set(Date(), forKey: snapshotUpdatedAtKeyPrefix + wallet)
    }

    private func loadSnapshot(wallet: String) -> [TokenBalance] {
        guard
            let data = defaults.data(forKey: snapshotKeyPrefix + wallet),
            let decoded = try? JSONDecoder().decode([TokenBalance].self, from: data)
        else {
            return []
        }
        return decoded
    }
}
