import Foundation

protocol TokenMetadataProviding {
    func metadata(for mint: String) async -> TokenMetadata
}

actor TokenMetadataService: TokenMetadataProviding {
    private let session: URLSession
    private let jupiterEndpoint: URL
    private let solanaTokenListEndpoint: URL
    private let solscanMetaBaseURL: URL
    private let dexscreenerTokenBaseURL: URL
    private var cache: [String: TokenMetadata] = [:]
    private var didLoadSeedData = false

    init(
        session: URLSession = .shared,
        jupiterEndpoint: URL = URL(string: "https://token.jup.ag/strict")!,
        solanaTokenListEndpoint: URL = URL(string: "https://cdn.jsdelivr.net/gh/solana-labs/token-list@main/src/tokens/solana.tokenlist.json")!,
        solscanMetaBaseURL: URL = URL(string: "https://public-api.solscan.io/token/meta?tokenAddress=")!,
        dexscreenerTokenBaseURL: URL = URL(string: "https://api.dexscreener.com/latest/dex/tokens/")!
    ) {
        self.session = session
        self.jupiterEndpoint = jupiterEndpoint
        self.solanaTokenListEndpoint = solanaTokenListEndpoint
        self.solscanMetaBaseURL = solscanMetaBaseURL
        self.dexscreenerTokenBaseURL = dexscreenerTokenBaseURL
    }

    func metadata(for mint: String) async -> TokenMetadata {
        if let cached = cache[mint] {
            return cached
        }

        await loadSeedDataIfNeeded()
        if let loaded = cache[mint] {
            return loaded
        }

        if let discovered = await loadOnDemandMetadata(for: mint) {
            cache[mint] = discovered
            return discovered
        }

        return TokenMetadata.fallback(mint: mint)
    }

    private func loadSeedDataIfNeeded() async {
        guard !didLoadSeedData else { return }
        didLoadSeedData = true

        async let jupiterLoad: [String: TokenMetadata] = loadJupiterTokens()
        async let solanaListLoad: [String: TokenMetadata] = loadSolanaTokenList()

        let jupiter = await jupiterLoad
        let solana = await solanaListLoad

        var merged = solana
        for (mint, metadata) in jupiter {
            if let existing = merged[mint] {
                merged[mint] = merge(primary: metadata, secondary: existing)
            } else {
                merged[mint] = metadata
            }
        }

        cache = merged
    }

    private func loadJupiterTokens() async -> [String: TokenMetadata] {
        do {
            let (data, response) = try await session.data(from: jupiterEndpoint)
            guard
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode)
            else {
                return [:]
            }

            let list = try JSONDecoder().decode([JupiterTokenEntry].self, from: data)
            return Dictionary(uniqueKeysWithValues: list.map { entry in
                let metadata = TokenMetadata(
                    mint: entry.address,
                    symbol: entry.symbol,
                    name: entry.name,
                    logoURL: makeURL(entry.logoURI),
                    tags: normalizeTags(entry.tags ?? []),
                    websiteURL: makeURL(entry.extensions?.website),
                    coingeckoID: entry.extensions?.coingeckoID,
                    verified: !(entry.tags ?? []).isEmpty || (entry.extensions?.coingeckoID != nil)
                )
                return (entry.address, metadata)
            })
        } catch {
            return [:]
        }
    }

    private func loadSolanaTokenList() async -> [String: TokenMetadata] {
        do {
            let (data, response) = try await session.data(from: solanaTokenListEndpoint)
            guard
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode)
            else {
                return [:]
            }

            let decoded = try JSONDecoder().decode(SolanaTokenListResponse.self, from: data)
            return Dictionary(uniqueKeysWithValues: decoded.tokens.map { entry in
                let metadata = TokenMetadata(
                    mint: entry.address,
                    symbol: entry.symbol,
                    name: entry.name,
                    logoURL: makeURL(entry.logoURI),
                    tags: normalizeTags(entry.tags ?? []),
                    websiteURL: makeURL(entry.extensions?.website),
                    coingeckoID: entry.extensions?.coingeckoID,
                    verified: (entry.tags ?? []).contains("verified") || (entry.tags ?? []).contains("community") || (entry.tags ?? []).contains("strict")
                )
                return (entry.address, metadata)
            })
        } catch {
            return [:]
        }
    }

    private func loadOnDemandMetadata(for mint: String) async -> TokenMetadata? {
        async let solscan = loadFromSolscan(mint: mint)
        async let dexscreener = loadFromDexScreener(mint: mint)

        let fromSolscan = await solscan
        let fromDexScreener = await dexscreener

        if let fromSolscan {
            if let fromDexScreener {
                return merge(primary: fromSolscan, secondary: fromDexScreener)
            }
            return fromSolscan
        }

        return fromDexScreener
    }

    private func loadFromSolscan(mint: String) async -> TokenMetadata? {
        guard
            let encodedMint = mint.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "\(solscanMetaBaseURL.absoluteString)\(encodedMint)")
        else {
            return nil
        }
        do {
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(SolscanTokenMetaResponse.self, from: data)
            return TokenMetadata(
                mint: mint,
                symbol: decoded.symbol ?? TokenMetadata.fallback(mint: mint).symbol,
                name: decoded.name ?? "Unknown Token",
                logoURL: makeURL(decoded.icon),
                tags: normalizeTags(decoded.tags ?? []),
                websiteURL: makeURL(decoded.website),
                coingeckoID: decoded.coingeckoID,
                verified: decoded.verified == true || decoded.name != nil
            )
        } catch {
            return nil
        }
    }

    private func loadFromDexScreener(mint: String) async -> TokenMetadata? {
        guard
            let encodedMint = mint.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "\(dexscreenerTokenBaseURL.absoluteString)\(encodedMint)")
        else {
            return nil
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(DexScreenerResponse.self, from: data)
            guard let token = decoded.pairs.first?.baseToken ?? decoded.pairs.first?.quoteToken else {
                return nil
            }

            let tags = decoded.pairs.flatMap { pair in
                (pair.labels ?? []) + (pair.info?.socials?.map { $0.type } ?? [])
            }
            let firstWebsite = decoded.pairs.compactMap { $0.info?.websites?.first?.url }.first
            let firstImage = decoded.pairs.compactMap { $0.info?.imageURL }.first

            return TokenMetadata(
                mint: mint,
                symbol: token.symbol,
                name: token.name,
                logoURL: makeURL(firstImage),
                tags: normalizeTags(tags),
                websiteURL: makeURL(firstWebsite),
                coingeckoID: nil,
                verified: true
            )
        } catch {
            return nil
        }
    }

    private func merge(primary: TokenMetadata, secondary: TokenMetadata) -> TokenMetadata {
        let mergedTags = Array(Set(primary.tags + secondary.tags)).sorted()
        return TokenMetadata(
            mint: primary.mint,
            symbol: primary.symbol.isEmpty ? secondary.symbol : primary.symbol,
            name: primary.name.isEmpty ? secondary.name : primary.name,
            logoURL: primary.logoURL ?? secondary.logoURL,
            tags: mergedTags,
            websiteURL: primary.websiteURL ?? secondary.websiteURL,
            coingeckoID: primary.coingeckoID ?? secondary.coingeckoID,
            verified: primary.verified || secondary.verified
        )
    }

    private func normalizeTags(_ tags: [String]) -> [String] {
        tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private func makeURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}

private struct JupiterTokenEntry: Decodable {
    let address: String
    let symbol: String
    let name: String
    let logoURI: String?
    let tags: [String]?
    let extensions: TokenExtensions?
}

private struct SolanaTokenListResponse: Decodable {
    let tokens: [SolanaTokenEntry]
}

private struct SolanaTokenEntry: Decodable {
    let address: String
    let symbol: String
    let name: String
    let logoURI: String?
    let tags: [String]?
    let extensions: TokenExtensions?
}

private struct TokenExtensions: Decodable {
    let website: String?
    let coingeckoID: String?

    enum CodingKeys: String, CodingKey {
        case website
        case coingeckoID = "coingeckoId"
    }
}

private struct SolscanTokenMetaResponse: Decodable {
    let symbol: String?
    let name: String?
    let icon: String?
    let website: String?
    let tags: [String]?
    let verified: Bool?
    let coingeckoID: String?

    enum CodingKeys: String, CodingKey {
        case symbol
        case name
        case icon
        case website
        case tags
        case verified
        case coingeckoID = "coingeckoId"
    }
}

private struct DexScreenerResponse: Decodable {
    let pairs: [DexScreenerPair]
}

private struct DexScreenerPair: Decodable {
    let baseToken: DexScreenerToken
    let quoteToken: DexScreenerToken
    let labels: [String]?
    let info: DexScreenerPairInfo?
}

private struct DexScreenerToken: Decodable {
    let symbol: String
    let name: String
}

private struct DexScreenerPairInfo: Decodable {
    let imageURL: String?
    let websites: [DexScreenerWebsite]?
    let socials: [DexScreenerSocial]?

    enum CodingKeys: String, CodingKey {
        case imageURL = "imageUrl"
        case websites
        case socials
    }
}

private struct DexScreenerWebsite: Decodable {
    let url: String
}

private struct DexScreenerSocial: Decodable {
    let type: String
}
