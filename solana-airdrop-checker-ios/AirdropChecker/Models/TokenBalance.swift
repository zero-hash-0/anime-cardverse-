import Foundation

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

    static func fallback(mint: String) -> TokenMetadata {
        TokenMetadata(mint: mint, symbol: shortMint(mint), name: "Unknown Token", logoURL: nil)
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

struct AirdropEvent: Identifiable, Hashable {
    let id = UUID()
    let mint: String
    let oldAmount: Decimal
    let newAmount: Decimal
    let metadata: TokenMetadata
    let risk: ClaimRiskAssessment
    let detectedAt: Date

    var delta: Decimal {
        newAmount - oldAmount
    }
}
