import Foundation
import SwiftUI

enum RiskHistoryRange: String, CaseIterable, Identifiable {
    case sevenDays = "7D"
    case thirtyDays = "30D"
    case ninetyDays = "90D"

    var id: String { rawValue }

    var dayCount: Int {
        switch self {
        case .sevenDays: return 7
        case .thirtyDays: return 30
        case .ninetyDays: return 90
        }
    }
}

enum ExposureTier: String, CaseIterable, Codable {
    case guarded = "Guarded"
    case stable = "Stable"
    case elevated = "Elevated"
    case critical = "Critical"

    var label: String { rawValue }

    var color: Color {
        switch self {
        case .guarded:
            return ThemeTokens.Accent.stable
        case .stable:
            return ThemeTokens.Accent.stable
        case .elevated:
            return ThemeTokens.Accent.elevated
        case .critical:
            return ThemeTokens.Accent.critical
        }
    }

    var dotOpacity: Double { 0.82 }
}

enum MonitoringIndicator: Equatable {
    case live
    case stale
    case degraded
}

enum EvidenceSeverity: String, Hashable {
    case low
    case elevated
    case critical

    var color: Color {
        switch self {
        case .low:
            return ThemeTokens.Accent.stable
        case .elevated:
            return ThemeTokens.Accent.elevated
        case .critical:
            return ThemeTokens.Accent.critical
        }
    }
}

struct EvidenceItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let severity: EvidenceSeverity
    let timestamp: Date
}

struct ExposureFactor: Identifiable, Hashable {
    let id: String
    let name: String
    let value: Int
    let delta24h: Double
    let weight: Double

    var severityColor: Color {
        RiskModel.tier(for: value).color
    }

    var weightPercentText: String {
        "Weight: \(Int((weight * 100).rounded()))%"
    }
}

struct ExposureSnapshot: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let exposureIndex: Int
    let tier: ExposureTier
    let factors: [ExposureFactor]
}

enum RiskModel {
    static let contractRiskWeight = 0.30
    static let protocolTrustInverseWeight = 0.20
    static let interactionVelocityWeight = 0.15
    static let assetVolatilityWeight = 0.15
    static let counterpartyRiskWeight = 0.20

    static let transparentWeights: [(String, Double)] = [
        ("Contract Risk Exposure", contractRiskWeight),
        ("System Integrity Inverse", protocolTrustInverseWeight),
        ("Interaction Velocity", interactionVelocityWeight),
        ("Asset Volatility Proxy", assetVolatilityWeight),
        ("Counterparty Risk", counterpartyRiskWeight)
    ]

    static func computeExposureIndex(from factors: [ExposureFactor]) -> Int {
        guard !factors.isEmpty else { return 0 }

        let weightedSum = factors.reduce(0.0) { partial, factor in
            partial + (Double(factor.value) * factor.weight)
        }

        return max(0, min(100, Int(weightedSum.rounded())))
    }

    static func tier(for index: Int) -> ExposureTier {
        switch index {
        case 0...25:
            return .guarded
        case 26...50:
            return .stable
        case 51...75:
            return .elevated
        default:
            return .critical
        }
    }
}
