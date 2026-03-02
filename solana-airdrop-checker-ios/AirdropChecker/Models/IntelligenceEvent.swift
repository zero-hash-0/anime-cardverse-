import Foundation

enum IntelligenceEventType: String, Codable {
    case scan
    case policy
    case risk
    case system
}

enum IntelligenceEventSeverity: String, Codable {
    case info
    case warning
    case critical
}

struct IntelligenceEvent: Identifiable, Codable, Equatable {
    let id: String
    let type: IntelligenceEventType
    let title: String
    let detail: String
    let timestamp: Date
    let severity: IntelligenceEventSeverity

    init(
        id: String = UUID().uuidString,
        type: IntelligenceEventType,
        title: String,
        detail: String,
        timestamp: Date = Date(),
        severity: IntelligenceEventSeverity
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.severity = severity
    }
}
