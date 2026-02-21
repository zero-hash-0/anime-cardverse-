import Foundation

protocol TokenMetadataProviding {
    func metadata(for mint: String) async -> TokenMetadata
}

actor TokenMetadataService: TokenMetadataProviding {
    private let session: URLSession
    private let endpoint: URL
    private var cache: [String: TokenMetadata] = [:]
    private var didLoadSeedData = false

    init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://token.jup.ag/strict")!
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    func metadata(for mint: String) async -> TokenMetadata {
        if let cached = cache[mint] {
            return cached
        }

        await loadSeedDataIfNeeded()
        if let loaded = cache[mint] {
            return loaded
        }

        return TokenMetadata.fallback(mint: mint)
    }

    private func loadSeedDataIfNeeded() async {
        guard !didLoadSeedData else { return }
        didLoadSeedData = true

        do {
            let (data, response) = try await session.data(from: endpoint)
            guard
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode)
            else {
                return
            }

            let list = try JSONDecoder().decode([TokenListEntry].self, from: data)
            cache = Dictionary(uniqueKeysWithValues: list.map {
                ($0.address, TokenMetadata(mint: $0.address, symbol: $0.symbol, name: $0.name, logoURL: URL(string: $0.logoURI ?? "")))
            })
        } catch {
            // Keep fallback behavior on metadata source failures.
        }
    }
}

private struct TokenListEntry: Decodable {
    let address: String
    let symbol: String
    let name: String
    let logoURI: String?
}
