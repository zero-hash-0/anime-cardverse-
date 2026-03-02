import SwiftUI

enum ProtectionLevel: String, CaseIterable, Identifiable, Codable, Hashable {
    case passive
    case alerting
    case hardened

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passive: return "Passive"
        case .alerting: return "Alerting"
        case .hardened: return "Hardened"
        }
    }

    var detail: String {
        switch self {
        case .passive:
            return "Monitoring only. Periodic scans and summary signals."
        case .alerting:
            return "Increased sensitivity. Alerts on exposure acceleration and high-risk events."
        case .hardened:
            return "Strict posture. Real-time anomaly detection and aggressive escalation."
        }
    }

    var severityColor: Color {
        switch self {
        case .passive:
            return ThemeTokens.Accent.intelligenceBlue
        case .alerting:
            return ThemeTokens.Accent.elevated
        case .hardened:
            return ThemeTokens.Accent.critical
        }
    }
}
