import Foundation

enum AlertDelivery: String, CaseIterable, Codable, Identifiable {
    case push
    case inApp
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .push: return "Push"
        case .inApp: return "In-app"
        case .both: return "Both"
        }
    }
}

enum Sensitivity: String, CaseIterable, Codable, Identifiable {
    case low
    case standard
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .standard: return "Standard"
        case .high: return "High"
        }
    }
}

struct ProtectionSettings: Codable, Equatable {
    var alertsEnabled: Bool
    var highRiskOnly: Bool
    var delivery: AlertDelivery
    var anomalySensitivity: Sensitivity
    var exposureDeltaNotifyPercent: Int
    var criticalThreshold: Int
    var autoScanIntervalMinutes: Int

    static func `default`(
        alertsEnabled: Bool = false,
        highRiskOnly: Bool = false,
        delivery: AlertDelivery = .inApp,
        anomalySensitivity: Sensitivity = .standard,
        exposureDeltaNotifyPercent: Int = 3,
        criticalThreshold: Int = 76,
        autoScanIntervalMinutes: Int = 60
    ) -> ProtectionSettings {
        ProtectionSettings(
            alertsEnabled: alertsEnabled,
            highRiskOnly: highRiskOnly,
            delivery: delivery,
            anomalySensitivity: anomalySensitivity,
            exposureDeltaNotifyPercent: exposureDeltaNotifyPercent,
            criticalThreshold: criticalThreshold,
            autoScanIntervalMinutes: autoScanIntervalMinutes
        )
    }
}
