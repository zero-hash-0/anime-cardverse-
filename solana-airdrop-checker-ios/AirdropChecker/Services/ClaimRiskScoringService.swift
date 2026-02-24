import Foundation

protocol ClaimRiskScoring {
    func evaluate(eventDelta: Decimal, metadata: TokenMetadata) -> ClaimRiskAssessment
}

struct ClaimRiskScoringService: ClaimRiskScoring {
    private let suspiciousKeywords = [
        "claim", "airdrop", "free", "bonus", "gift", "reward", "visit", "http", "www"
    ]

    func evaluate(eventDelta: Decimal, metadata: TokenMetadata) -> ClaimRiskAssessment {
        var score = 0
        var reasons: [String] = []

        let symbolLower = metadata.symbol.lowercased()
        let nameLower = metadata.name.lowercased()

        if metadata.name == "Unknown Token" {
            score += 30
            reasons.append("Token metadata not found in trusted list.")
        }

        if !metadata.verified {
            score += 15
            reasons.append("Token is not marked verified in aggregated metadata sources.")
        }

        if metadata.logoURL == nil {
            score += 8
            reasons.append("Token has no known logo; manually verify mint before interacting.")
        }

        if suspiciousKeywords.contains(where: { symbolLower.contains($0) || nameLower.contains($0) }) {
            score += 35
            reasons.append("Token name/symbol contains common scam keywords.")
        }

        if eventDelta <= 0.001 {
            score += 20
            reasons.append("Tiny balance increase; dust airdrops can be phishing bait.")
        }

        if metadata.symbol.count > 10 {
            score += 10
            reasons.append("Unusually long token symbol.")
        }

        if metadata.tags.contains("nft") || metadata.tags.contains("collectible") {
            score += 7
            reasons.append("Token is tagged as NFT/collectible; claim prompts may differ from fungible token drops.")
        }

        let level: ClaimRiskLevel
        switch score {
        case 0..<30:
            level = .low
            if reasons.isEmpty {
                reasons = ["No obvious risk indicators detected."]
            }
        case 30..<65:
            level = .medium
        default:
            level = .high
        }

        return ClaimRiskAssessment(level: level, score: min(score, 100), reasons: reasons)
    }
}
