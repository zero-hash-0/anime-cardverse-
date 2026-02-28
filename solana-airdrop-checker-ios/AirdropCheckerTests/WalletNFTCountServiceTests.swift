import XCTest
@testable import PrismMesh

final class WalletNFTCountServiceTests: XCTestCase {
    func testCountsStandardAndCompressedNFTs() async throws {
        let rpc = MockNFTRPC(
            candidates: [
                "mint_standard_1",
                "mint_standard_2",
                "mint_reject_supply"
            ],
            supplyByMint: [
                "mint_standard_1": TokenSupplyInfo(amount: "1", decimals: 0),
                "mint_standard_2": TokenSupplyInfo(amount: "1", decimals: 0),
                "mint_reject_supply": TokenSupplyInfo(amount: "1000000", decimals: 6)
            ]
        )
        let compressed = MockCompressedNFTProvider(count: 12)
        let service = WalletNFTCountService(
            rpcClient: rpc,
            compressedProvider: compressed,
            errorTracker: NFTMockErrorTracker()
        )

        let counts = try await service.fetchCounts(wallet: "KnownNFTWallet111111111111111111111111111111")

        XCTAssertEqual(counts.standardNFTCount, 2)
        XCTAssertEqual(counts.compressedNFTCount, 12)
        XCTAssertEqual(counts.total, 14)
        XCTAssertGreaterThan(counts.total, 0)
    }
}

private final class MockNFTRPC: SolanaRPCFetching {
    let candidates: [String]
    let supplyByMint: [String: TokenSupplyInfo]

    init(candidates: [String], supplyByMint: [String: TokenSupplyInfo]) {
        self.candidates = candidates
        self.supplyByMint = supplyByMint
    }

    func fetchTokenBalances(owner: String) async throws -> [TokenBalance] {
        []
    }

    func getTokenAccountsByOwnerParsed(owner: String) async throws -> [SolanaParsedTokenAccount] {
        []
    }

    func getMultipleAccounts(pubkeys: [String]) async throws -> [SolanaAccountLookupValue?] {
        []
    }

    func getAccountInfo(pubkey: String) async throws -> SolanaAccountLookupValue? {
        nil
    }

    func fetchStandardNFTMintCandidates(owner: String) async throws -> [String] {
        candidates
    }

    func fetchTokenSupply(mint: String) async throws -> TokenSupplyInfo {
        guard let supply = supplyByMint[mint] else {
            throw SolanaRPCError.invalidResponse
        }
        return supply
    }
}

private struct MockCompressedNFTProvider: CompressedNFTCounting {
    let count: Int

    func fetchCompressedNFTCount(owner: String) async throws -> Int {
        count
    }
}

private actor NFTMockErrorTracker: ErrorTracking {
    func capture(category: String, message: String, httpStatus: Int?, extra: [String: String]) async {}
    func setUser(hashedWallet: String?) async {}
    func breadcrumb(category: String, message: String, data: [String: String]) async {}
}
