import Foundation

protocol EventHistoryStoring {
    func load() -> [AirdropEvent]
    func save(newEvents: [AirdropEvent])
    func clear()
}

final class EventHistoryStore: EventHistoryStoring {
    private let defaults: UserDefaults
    private let key = "airdrop_event_history"
    private let maxItems: Int

    init(defaults: UserDefaults = .standard, maxItems: Int = 300) {
        self.defaults = defaults
        self.maxItems = maxItems
    }

    func load() -> [AirdropEvent] {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([AirdropEvent].self, from: data)
        else {
            return []
        }

        return decoded.sorted { $0.detectedAt > $1.detectedAt }
    }

    func save(newEvents: [AirdropEvent]) {
        guard !newEvents.isEmpty else { return }

        var combined = load()
        combined.insert(contentsOf: newEvents, at: 0)

        var seen = Set<String>()
        combined = combined.filter {
            let signature = "\($0.wallet)|\($0.mint)|\($0.newAmount)|\($0.detectedAt.timeIntervalSince1970)"
            return seen.insert(signature).inserted
        }
        if combined.count > maxItems {
            combined = Array(combined.prefix(maxItems))
        }

        guard let encoded = try? JSONEncoder().encode(combined) else { return }
        defaults.set(encoded, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
