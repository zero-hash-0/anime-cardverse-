import Foundation

struct JupiterHolding: Identifiable, Hashable {
    var id: String { mint }
    let mint: String
    let symbol: String
    let name: String
    let amount: Decimal
    let usdValue: Decimal
    let priceUSD: Decimal?
    let logoURL: URL?
    let tags: [String]
}

struct JupiterPortfolioSnapshot: Hashable {
    let owner: String
    let fetchedAt: Date
    let netWorthUSD: Decimal
    let stakedJup: Decimal
    let holdings: [JupiterHolding]
    let platformCount: Int
}

enum JupiterPortfolioError: LocalizedError {
    case apiKeyMissing
    case unauthorized
    case invalidResponse
    case transportError(String)

    var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Add your Jupiter API key in Advanced settings to sync portfolio data."
        case .unauthorized:
            return "Jupiter API key unauthorized. Update your key in Advanced settings."
        case .invalidResponse:
            return "Could not decode Jupiter portfolio response."
        case .transportError(let message):
            return message
        }
    }
}
