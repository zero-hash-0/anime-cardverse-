import Foundation

final class AirdropMonitorService {
    private let rpcClient: SolanaRPCFetching
    private let metadataService: TokenMetadataProviding
    private let riskScoring: ClaimRiskScoring
    private let defaults: UserDefaults
    private let snapshotKeyPrefix = "wallet_snapshot_"

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

        let previousByMint = Dictionary(uniqueKeysWithValues: previous.map { ($0.mint, $0.amount) })

        var events: [AirdropEvent] = []
        events.reserveCapacity(current.count)

        for token in current {
            let oldAmount = previousByMint[token.mint] ?? 0
            guard token.amount > oldAmount else { continue }

            let metadata = await metadataService.metadata(for: token.mint)
            let risk = riskScoring.evaluate(eventDelta: token.amount - oldAmount, metadata: metadata)

            events.append(AirdropEvent(
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

    private func saveSnapshot(_ snapshot: [TokenBalance], wallet: String) {
        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(encoded, forKey: snapshotKeyPrefix + wallet)
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
