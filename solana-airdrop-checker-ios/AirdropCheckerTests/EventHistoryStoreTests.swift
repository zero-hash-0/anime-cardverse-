import XCTest
@testable import AirdropChecker

final class EventHistoryStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() {
        let defaults = UserDefaults(suiteName: "EventHistoryStoreTests")!
        defaults.removePersistentDomain(forName: "EventHistoryStoreTests")

        let store = EventHistoryStore(defaults: defaults, maxItems: 10)
        let event = AirdropEvent(
            wallet: "wallet",
            mint: "mint",
            oldAmount: 1,
            newAmount: 2,
            metadata: TokenMetadata(mint: "mint", symbol: "TKN", name: "Token", logoURL: nil),
            risk: ClaimRiskAssessment(level: .low, score: 0, reasons: ["ok"]),
            detectedAt: Date()
        )

        store.save(newEvents: [event])
        let loaded = store.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.mint, "mint")
        XCTAssertEqual(loaded.first?.wallet, "wallet")
    }
}
