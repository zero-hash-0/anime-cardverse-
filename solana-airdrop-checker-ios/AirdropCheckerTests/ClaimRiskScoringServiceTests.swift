import XCTest
@testable import AirdropChecker

final class ClaimRiskScoringServiceTests: XCTestCase {
    private let service = ClaimRiskScoringService()

    func testUnknownDustTokenIsHighRisk() {
        let metadata = TokenMetadata(mint: "mint", symbol: "FREECLAIM", name: "Unknown Token", logoURL: nil)
        let result = service.evaluate(eventDelta: 0.0001, metadata: metadata)

        XCTAssertEqual(result.level, .high)
        XCTAssertGreaterThanOrEqual(result.score, 65)
    }

    func testKnownTokenWithNormalDeltaIsLowRisk() {
        let metadata = TokenMetadata(mint: "mint", symbol: "USDC", name: "USD Coin", logoURL: nil)
        let result = service.evaluate(eventDelta: 10, metadata: metadata)

        XCTAssertEqual(result.level, .low)
    }
}
