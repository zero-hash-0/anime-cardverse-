import XCTest
@testable import AirdropChecker

final class AirdropMonitorServiceTests: XCTestCase {
    func testDetectsPositiveBalanceDeltas() async throws {
        let defaults = UserDefaults(suiteName: "AirdropMonitorServiceTests")!
        defaults.removePersistentDomain(forName: "AirdropMonitorServiceTests")

        let rpc = MockRPC(
            snapshots: [
                [TokenBalance(mint: "mint1", amount: 1)],
                [TokenBalance(mint: "mint1", amount: 3)]
            ]
        )

        let service = AirdropMonitorService(
            rpcClient: rpc,
            metadataService: MockMetadata(),
            riskScoring: ClaimRiskScoringService(),
            defaults: defaults
        )

        _ = try await service.checkForAirdrops(wallet: "wallet")
        let events = try await service.checkForAirdrops(wallet: "wallet")

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.mint, "mint1")
        XCTAssertEqual(events.first?.delta, 2)
    }
}

private final class MockRPC: SolanaRPCFetching {
    private let snapshots: [[TokenBalance]]
    private var index = 0

    init(snapshots: [[TokenBalance]]) {
        self.snapshots = snapshots
    }

    func fetchTokenBalances(owner: String) async throws -> [TokenBalance] {
        defer { index += 1 }
        return snapshots[min(index, snapshots.count - 1)]
    }
}

private actor MockMetadata: TokenMetadataProviding {
    func metadata(for mint: String) async -> TokenMetadata {
        TokenMetadata(mint: mint, symbol: "TKN", name: "Token", logoURL: nil)
    }
}
