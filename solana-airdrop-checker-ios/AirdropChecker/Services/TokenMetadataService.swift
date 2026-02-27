import CryptoKit
import Foundation
import UIKit

protocol TokenMetadataProviding {
    func metadata(for mint: String) async -> TokenMetadata
}

actor TokenMetadataService: TokenMetadataProviding {
    nonisolated static let shared = TokenMetadataService()
    private static let defaultJupiterEndpoint = URL(string: "https://token.jup.ag/strict")
    private static let defaultSolanaTokenListEndpoint = URL(string: "https://cdn.jsdelivr.net/gh/solana-labs/token-list@main/src/tokens/solana.tokenlist.json")
    private static let defaultSolscanMetaBaseURL = URL(string: "https://public-api.solscan.io/token/meta?tokenAddress=")
    private static let defaultDexscreenerTokenBaseURL = URL(string: "https://api.dexscreener.com/latest/dex/tokens/")
    private let session: URLSession
    private let jupiterEndpoint: URL
    private let solanaTokenListEndpoint: URL
    private let solscanMetaBaseURL: URL
    private let dexscreenerTokenBaseURL: URL
    private let errorTracker: ErrorTracking
    private var cache: [String: TokenMetadata] = [:]
    private var didLoadSeedData = false
    private var didStartSeedDataLoad = false

    init(
        session: URLSession = .shared,
        jupiterEndpoint: URL = TokenMetadataService.defaultJupiterEndpoint ?? URL(fileURLWithPath: "/"),
        solanaTokenListEndpoint: URL = TokenMetadataService.defaultSolanaTokenListEndpoint ?? URL(fileURLWithPath: "/"),
        solscanMetaBaseURL: URL = TokenMetadataService.defaultSolscanMetaBaseURL ?? URL(fileURLWithPath: "/"),
        dexscreenerTokenBaseURL: URL = TokenMetadataService.defaultDexscreenerTokenBaseURL ?? URL(fileURLWithPath: "/"),
        errorTracker: ErrorTracking = ErrorTrackerService.shared
    ) {
        self.session = session
        self.jupiterEndpoint = jupiterEndpoint
        self.solanaTokenListEndpoint = solanaTokenListEndpoint
        self.solscanMetaBaseURL = solscanMetaBaseURL
        self.dexscreenerTokenBaseURL = dexscreenerTokenBaseURL
        self.errorTracker = errorTracker
    }

    func metadata(for mint: String) async -> TokenMetadata {
        let normalizedMint = normalizeMintKey(mint)
        if let cached = cache[normalizedMint] {
            return cached
        }

        triggerSeedDataLoadIfNeeded()

        if let discovered = await loadOnDemandMetadata(for: mint) {
            cache[normalizedMint] = discovered
            return discovered
        }

        return TokenMetadata.fallback(mint: mint)
    }

    func metadata(forSymbol symbol: String) async -> TokenMetadata? {
        let normalizedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedSymbol.isEmpty else { return nil }
        triggerSeedDataLoadIfNeeded()
        await loadSeedDataIfNeeded()
        return cache.values.first { $0.symbol.uppercased() == normalizedSymbol }
    }

    func mint(forSymbol symbol: String) async -> String? {
        await metadata(forSymbol: symbol)?.mint
    }

    func prewarmSeedData() {
        triggerSeedDataLoadIfNeeded()
    }

    private func triggerSeedDataLoadIfNeeded() {
        guard !didStartSeedDataLoad else { return }
        didStartSeedDataLoad = true
        Task { [weak self] in
            await self?.loadSeedDataIfNeeded()
        }
    }

    private func loadSeedDataIfNeeded() async {
        guard !didLoadSeedData else { return }
        didLoadSeedData = true
        let merged = await loadSeedMetadataSnapshot()
        cache.merge(merged) { _, new in new }
    }

    private func loadSeedMetadataSnapshot() async -> [String: TokenMetadata] {
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
        return merged
    }

    private func loadJupiterTokens() async -> [String: TokenMetadata] {
        do {
            let (data, response) = try await fetchData(url: jupiterEndpoint)
            guard
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode)
            else {
                return [:]
            }

            let list = try JSONDecoder().decode([JupiterTokenEntry].self, from: data)
            let entries = list.map { entry in
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
                return (mint: entry.address, metadata: metadata)
            }
            return await buildMintMetadataMap(from: entries, source: "jupiter_token_list")
        } catch {
            await errorTracker.capture(
                category: "metadata_load_error",
                message: error.localizedDescription,
                httpStatus: nil,
                extra: ["source": "jupiter_token_list"]
            )
            return [:]
        }
    }

    private func loadSolanaTokenList() async -> [String: TokenMetadata] {
        do {
            let (data, response) = try await fetchData(url: solanaTokenListEndpoint)
            guard
                let http = response as? HTTPURLResponse,
                (200...299).contains(http.statusCode)
            else {
                return [:]
            }
            return await parseSolanaTokenListData(data)
        } catch {
            await errorTracker.capture(
                category: "metadata_load_error",
                message: error.localizedDescription,
                httpStatus: nil,
                extra: ["source": "solana_token_list"]
            )
            return [:]
        }
    }

    func parseSolanaTokenListData(_ data: Data) async -> [String: TokenMetadata] {
        do {
            let decoded = try JSONDecoder().decode(SolanaTokenListResponse.self, from: data)
            let entries = decoded.tokens.map { entry in
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
                return (mint: entry.address, metadata: metadata)
            }
            return await buildMintMetadataMap(from: entries, source: "solana_token_list")
        } catch {
            await errorTracker.capture(
                category: "metadata_parse_error",
                message: error.localizedDescription,
                httpStatus: nil,
                extra: ["source": "solana_token_list"]
            )
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
            request.timeoutInterval = 10
            let (data, response) = try await fetchData(request: request)
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
            await errorTracker.capture(
                category: "metadata_load_error",
                message: error.localizedDescription,
                httpStatus: nil,
                extra: ["source": "solscan"]
            )
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
            let (data, response) = try await fetchData(url: url)
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
            await errorTracker.capture(
                category: "metadata_load_error",
                message: error.localizedDescription,
                httpStatus: nil,
                extra: ["source": "dexscreener"]
            )
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
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        guard var components = URLComponents(string: raw) else { return nil }
        guard let scheme = components.scheme?.lowercased() else { return nil }
        if scheme == "http" {
            components.scheme = "https"
            return components.url
        }
        guard scheme == "https" else { return nil }
        return components.url
    }

    private func fetchData(url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        return try await fetchData(request: request)
    }

    private func fetchData(request: URLRequest, maxAttempts: Int = 3) async throws -> (Data, URLResponse) {
        var attempt = 0
        var delayNs: UInt64 = 300_000_000
        var lastError: Error = URLError(.badServerResponse)

        while attempt < maxAttempts {
            do {
                return try await session.data(for: request)
            } catch {
                lastError = error
                attempt += 1
                if attempt >= maxAttempts { break }
                try? await Task.sleep(nanoseconds: delayNs)
                delayNs = min(delayNs * 2, 2_000_000_000)
            }
        }
        await errorTracker.capture(
            category: (lastError as? URLError)?.code == .timedOut ? "network_timeout" : "network_error",
            message: lastError.localizedDescription,
            httpStatus: nil,
            extra: ["service": "token_metadata"]
        )
        throw lastError
    }

    private func buildMintMetadataMap(
        from entries: [(mint: String, metadata: TokenMetadata)],
        source: String
    ) async -> [String: TokenMetadata] {
        var metadataByMint: [String: TokenMetadata] = [:]
        var countsByMint: [String: Int] = [:]

        for entry in entries {
            let key = normalizeMintKey(entry.mint)
            guard !key.isEmpty else { continue }
            countsByMint[key, default: 0] += 1
            if metadataByMint[key] == nil {
                metadataByMint[key] = entry.metadata
            }
        }

        let duplicateCounts = countsByMint
            .filter { $0.value > 1 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }

        if !duplicateCounts.isEmpty {
            let topDuplicateSummary = duplicateCounts
                .prefix(20)
                .map { "\($0.key):\($0.value)" }
                .joined(separator: ",")
            print("[TokenMetadataService] source=\(source) total=\(entries.count) unique=\(metadataByMint.count) duplicateKeys=\(duplicateCounts.count) top20=\(topDuplicateSummary)")
            await errorTracker.capture(
                category: "token_list_duplicates_detected",
                message: "Token list duplicates detected for \(source)",
                httpStatus: nil,
                extra: [
                    "source": source,
                    "totalEntries": String(entries.count),
                    "uniqueKeys": String(metadataByMint.count),
                    "duplicateKeyCount": String(duplicateCounts.count),
                    "top20": topDuplicateSummary
                ]
            )
        } else {
            print("[TokenMetadataService] source=\(source) total=\(entries.count) unique=\(metadataByMint.count) duplicateKeys=0")
        }

        return metadataByMint
    }

    private func normalizeMintKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

actor TokenIconService {
    nonisolated static let shared = TokenIconService()

    private let session: URLSession
    private let metadataService: TokenMetadataService
    private let fileManager: FileManager
    private let memoryCache = NSCache<NSURL, UIImage>()
    private let cacheDirectory: URL

    init(
        session: URLSession = .shared,
        metadataService: TokenMetadataService = .shared,
        fileManager: FileManager = .default
    ) {
        self.session = session
        self.metadataService = metadataService
        self.fileManager = fileManager
        self.cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrismMeshTokenIcons", isDirectory: true)
    }

    func resolvedLogoURL(logoURL: URL?, mint: String?, symbol: String?) async -> URL? {
        await resolveURL(logoURL: logoURL, mint: mint, symbol: symbol)
    }

    func image(for logoURL: URL?, mint: String?, symbol: String?) async -> UIImage? {
        let resolvedURL = await resolvedLogoURL(logoURL: logoURL, mint: mint, symbol: symbol)
        guard let resolvedURL else { return nil }
        return await image(for: resolvedURL)
    }

    private func resolveURL(logoURL: URL?, mint: String?, symbol: String?) async -> URL? {
        if let logoURL { return logoURL }
        if let mint, !mint.isEmpty {
            return await metadataService.metadata(for: mint).logoURL
        }
        if let symbol, !symbol.isEmpty, let metadata = await metadataService.metadata(forSymbol: symbol) {
            return metadata.logoURL
        }
        return nil
    }

    private func image(for url: URL) async -> UIImage? {
        let nsURL = url as NSURL
        if let image = memoryCache.object(forKey: nsURL) {
#if DEBUG
            print("[ICON] hit_cache=memory url=\(url.absoluteString)")
#endif
            return image
        }

        do {
            if let image = try loadDiskImage(for: url) {
                memoryCache.setObject(image, forKey: nsURL)
#if DEBUG
                print("[ICON] hit_cache=disk url=\(url.absoluteString)")
#endif
                return image
            }
        } catch {
#if DEBUG
            print("[ICON] disk_read_error url=\(url.absoluteString) error=\(error.localizedDescription)")
#endif
        }

        if let downloaded = await downloadImage(from: url) {
            memoryCache.setObject(downloaded, forKey: nsURL)
            do {
                try persistDiskImage(downloaded, for: url)
            } catch {
#if DEBUG
                print("[ICON] disk_write_error url=\(url.absoluteString) error=\(error.localizedDescription)")
#endif
            }
#if DEBUG
            print("[ICON] hit_cache=network url=\(url.absoluteString)")
#endif
            return downloaded
        }

#if DEBUG
        print("[ICON] hit_cache=miss url=\(url.absoluteString)")
#endif
        return nil
    }

    private func downloadImage(from url: URL) async -> UIImage? {
        var attempt = 0
        var delayNs: UInt64 = 250_000_000
        while attempt < 3 {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 8
                request.cachePolicy = .returnCacheDataElseLoad
                let (data, response) = try await session.data(for: request)
                guard
                    let http = response as? HTTPURLResponse,
                    (200...299).contains(http.statusCode),
                    let image = UIImage(data: data)
                else {
                    return nil
                }
                return image
            } catch {
                attempt += 1
                if attempt >= 3 { break }
                try? await Task.sleep(nanoseconds: delayNs)
                delayNs = min(delayNs * 2, 1_000_000_000)
            }
        }
        return nil
    }

    private func loadDiskImage(for url: URL) throws -> UIImage? {
        let fileURL = try cacheFileURL(for: url)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return UIImage(data: data)
    }

    private func persistDiskImage(_ image: UIImage, for url: URL) throws {
        guard let data = image.pngData() else { return }
        let fileURL = try cacheFileURL(for: url)
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        try data.write(to: fileURL, options: [.atomic])
    }

    private func cacheFileURL(for url: URL) throws -> URL {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(key).png")
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
