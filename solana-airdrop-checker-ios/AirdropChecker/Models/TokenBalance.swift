import Foundation

enum EventFeedFilter: String, CaseIterable, Identifiable {
    case latest
    case watchlist
    case history
    case highRisk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .latest: return "Latest"
        case .history: return "History"
        case .highRisk: return "Risk"
        case .watchlist: return "Watchlist"
        }
    }
}

struct TokenBalance: Codable, Identifiable, Hashable {
    var id: String { mint }
    let mint: String
    let amount: Decimal
}

struct TokenMetadata: Codable, Hashable {
    let mint: String
    let symbol: String
    let name: String
    let logoURL: URL?
    let tags: [String]
    let websiteURL: URL?
    let coingeckoID: String?
    let verified: Bool

    init(
        mint: String,
        symbol: String,
        name: String,
        logoURL: URL?,
        tags: [String] = [],
        websiteURL: URL? = nil,
        coingeckoID: String? = nil,
        verified: Bool = false
    ) {
        self.mint = mint
        self.symbol = symbol
        self.name = name
        self.logoURL = logoURL
        self.tags = tags
        self.websiteURL = websiteURL
        self.coingeckoID = coingeckoID
        self.verified = verified
    }

    enum CodingKeys: String, CodingKey {
        case mint
        case symbol
        case name
        case logoURL
        case tags
        case websiteURL
        case coingeckoID
        case verified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mint = try container.decode(String.self, forKey: .mint)
        symbol = try container.decode(String.self, forKey: .symbol)
        name = try container.decode(String.self, forKey: .name)
        logoURL = try container.decodeIfPresent(URL.self, forKey: .logoURL)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        websiteURL = try container.decodeIfPresent(URL.self, forKey: .websiteURL)
        coingeckoID = try container.decodeIfPresent(String.self, forKey: .coingeckoID)
        verified = try container.decodeIfPresent(Bool.self, forKey: .verified) ?? false
    }

    static func fallback(mint: String) -> TokenMetadata {
        TokenMetadata(
            mint: mint,
            symbol: shortMint(mint),
            name: "Unknown Token",
            logoURL: nil,
            tags: ["unverified"],
            websiteURL: nil,
            coingeckoID: nil,
            verified: false
        )
    }

    private static func shortMint(_ value: String) -> String {
        guard value.count > 10 else { return value }
        return "\(value.prefix(4))...\(value.suffix(4))"
    }
}

enum ClaimRiskLevel: String, Codable, CaseIterable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low: return "Low Risk"
        case .medium: return "Medium Risk"
        case .high: return "High Risk"
        }
    }
}

struct ClaimRiskAssessment: Codable, Hashable {
    let level: ClaimRiskLevel
    let score: Int
    let reasons: [String]
}

struct AirdropEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let wallet: String
    let mint: String
    let oldAmount: Decimal
    let newAmount: Decimal
    let metadata: TokenMetadata
    let risk: ClaimRiskAssessment
    let detectedAt: Date

    init(
        id: UUID = UUID(),
        wallet: String,
        mint: String,
        oldAmount: Decimal,
        newAmount: Decimal,
        metadata: TokenMetadata,
        risk: ClaimRiskAssessment,
        detectedAt: Date
    ) {
        self.id = id
        self.wallet = wallet
        self.mint = mint
        self.oldAmount = oldAmount
        self.newAmount = newAmount
        self.metadata = metadata
        self.risk = risk
        self.detectedAt = detectedAt
    }

    var delta: Decimal {
        newAmount - oldAmount
    }
}
