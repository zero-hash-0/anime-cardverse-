import Foundation

enum NFTSummaryDataSource: String, Equatable {
    case heliusDAS
    case rpcFallback
}

struct NFTSummaryDebug: Equatable {
    let candidates: Int
    let metadataFound: Int
    let editionsFound: Int
    let compressedFound: Int
    let pagesFetched: Int
    let pageLimit: Int
    let totalAssetsSeen: Int
    let excludedFungible: Int
    let countedNFT: Int
    let countedUnknown: Int
    let droppedOther: Int

    static let zero = NFTSummaryDebug(
        candidates: 0,
        metadataFound: 0,
        editionsFound: 0,
        compressedFound: 0,
        pagesFetched: 0,
        pageLimit: 0,
        totalAssetsSeen: 0,
        excludedFungible: 0,
        countedNFT: 0,
        countedUnknown: 0,
        droppedOther: 0
    )
}

struct NFTSummary: Equatable {
    let totalCount: Int
    let compressedCount: Int
    let uncompressedCount: Int
    let unknownCount: Int
    let dataSource: NFTSummaryDataSource
    let debug: NFTSummaryDebug

    static let zero = NFTSummary(
        totalCount: 0,
        compressedCount: 0,
        uncompressedCount: 0,
        unknownCount: 0,
        dataSource: .rpcFallback,
        debug: .zero
    )
}

struct WalletNFTCounts: Equatable {
    let standardNFTCount: Int
    let compressedNFTCount: Int

    var total: Int {
        standardNFTCount + compressedNFTCount
    }

    static let zero = WalletNFTCounts(standardNFTCount: 0, compressedNFTCount: 0)
}

struct NFTCountDiagnostics: Equatable {
    let candidates: Int
    let metadataFound: Int
    let editionsFound: Int
    let compressedFound: Int

    static let zero = NFTCountDiagnostics(candidates: 0, metadataFound: 0, editionsFound: 0, compressedFound: 0)

    var summary: String {
        "NFT candidates: \(candidates) | metadata found: \(metadataFound) | editions found: \(editionsFound) | compressed: \(compressedFound)"
    }
}

struct NFTCountFetchResult: Equatable {
    let counts: WalletNFTCounts
    let diagnostics: NFTCountDiagnostics
}

protocol WalletNFTCounting {
    func fetchNFTSummary(owner: String) async throws -> NFTSummary
    func fetchCounts(wallet: String) async throws -> WalletNFTCounts
    func fetchDetailedCounts(wallet: String) async throws -> NFTCountFetchResult
}

protocol CompressedNFTCounting {
    func fetchCompressedNFTCount(owner: String) async throws -> Int
}

private protocol NFTSummaryProviding {
    func fetchNFTSummary(owner: String) async throws -> NFTSummary
}

final class WalletNFTCountService: WalletNFTCounting {
    private let rpcClient: SolanaRPCFetching
    private let compressedProvider: CompressedNFTCounting?
    private let errorTracker: ErrorTracking

    init(
        rpcClient: SolanaRPCFetching,
        compressedProvider: CompressedNFTCounting?,
        errorTracker: ErrorTracking = ErrorTrackerService.shared
    ) {
        self.rpcClient = rpcClient
        self.compressedProvider = compressedProvider
        self.errorTracker = errorTracker
    }

    func fetchNFTSummary(owner: String) async throws -> NFTSummary {
        if let provider = compressedProvider as? NFTSummaryProviding {
            await errorTracker.capture(
                category: "helius_configured",
                message: "using helius DAS",
                httpStatus: nil,
                extra: ["wallet": owner]
            )
            let summary = try await provider.fetchNFTSummary(owner: owner)
#if DEBUG
            print("[NFT] wallet=\(owner) source=\(summary.dataSource.rawValue) total=\(summary.totalCount) compressed=\(summary.compressedCount) uncompressed=\(summary.uncompressedCount) unknown=\(summary.unknownCount)")
            print("[NFT] pages=\(summary.debug.pagesFetched) limit=\(summary.debug.pageLimit) assets=\(summary.debug.totalAssetsSeen)")
#endif
            return summary
        }
        await errorTracker.capture(
            category: "helius_not_configured",
            message: "compressedProvider nil; using rpcFallback",
            httpStatus: nil,
            extra: ["wallet": owner]
        )

        let diagnostics = try await rpcClient.fetchNFTHoldings(owner: owner)
        let uncompressed = diagnostics.holdings.filter { !$0.isCompressed }.count
        var compressed = diagnostics.holdings.filter { $0.isCompressed }.count
        if compressed == 0, let compressedProvider {
            do {
                compressed = try await compressedProvider.fetchCompressedNFTCount(owner: owner)
            } catch {
                await errorTracker.capture(
                    category: "nft_counting_compressed_failed",
                    message: error.localizedDescription,
                    httpStatus: nil,
                    extra: ["wallet": owner]
                )
            }
        }
        let unknown = max(0, diagnostics.candidates - (uncompressed + compressed))

        let summary = NFTSummary(
            totalCount: uncompressed + compressed,
            compressedCount: compressed,
            uncompressedCount: uncompressed,
            unknownCount: unknown,
            dataSource: .rpcFallback,
            debug: NFTSummaryDebug(
                candidates: diagnostics.candidates,
                metadataFound: diagnostics.metadataFound,
                editionsFound: diagnostics.editionsFound,
                compressedFound: diagnostics.compressedFound,
                pagesFetched: 0,
                pageLimit: 0,
                totalAssetsSeen: diagnostics.candidates,
                excludedFungible: 0,
                countedNFT: uncompressed + compressed,
                countedUnknown: unknown,
                droppedOther: 0
            )
        )
#if DEBUG
        print("[NFT] wallet=\(owner) source=rpcFallback total=\(summary.totalCount) compressed=\(summary.compressedCount) uncompressed=\(summary.uncompressedCount) unknown=\(summary.unknownCount)")
#endif
        return summary
    }

    func fetchCounts(wallet: String) async throws -> WalletNFTCounts {
        let summary = try await fetchNFTSummary(owner: wallet)
        return WalletNFTCounts(
            standardNFTCount: summary.uncompressedCount,
            compressedNFTCount: summary.compressedCount
        )
    }

    func fetchDetailedCounts(wallet: String) async throws -> NFTCountFetchResult {
        let summary = try await fetchNFTSummary(owner: wallet)
        let counts = WalletNFTCounts(
            standardNFTCount: summary.uncompressedCount,
            compressedNFTCount: summary.compressedCount
        )
        let diagnostics = NFTCountDiagnostics(
            candidates: summary.debug.candidates,
            metadataFound: summary.debug.metadataFound,
            editionsFound: summary.debug.editionsFound,
            compressedFound: summary.debug.compressedFound
        )
        return NFTCountFetchResult(counts: counts, diagnostics: diagnostics)
    }

#if DEBUG
    func debugPrintSummary(owner: String) async {
        do {
            let summary = try await fetchNFTSummary(owner: owner)
            print("[NFT][Summary] wallet=\(owner) total=\(summary.totalCount) compressed=\(summary.compressedCount) uncompressed=\(summary.uncompressedCount) unknown=\(summary.unknownCount) source=\(summary.dataSource.rawValue)")
            print("[NFT][Summary] pages=\(summary.debug.pagesFetched) limit=\(summary.debug.pageLimit) assets=\(summary.debug.totalAssetsSeen)")
        } catch {
            print("[NFT][Summary] wallet=\(owner) failed: \(error.localizedDescription)")
        }
    }
#endif
}

final class HeliusCompressedNFTProvider: CompressedNFTCounting {
    private let endpoint: URL
    private let session: URLSession
    private let errorTracker: ErrorTracking

    init(
        endpoint: URL,
        session: URLSession = .shared,
        errorTracker: ErrorTracking = ErrorTrackerService.shared
    ) {
        self.endpoint = endpoint
        self.session = session
        self.errorTracker = errorTracker
    }

    func fetchCompressedNFTCount(owner: String) async throws -> Int {
        let summary = try await fetchNFTSummary(owner: owner)
        return summary.compressedCount
    }
}

extension HeliusCompressedNFTProvider: NFTSummaryProviding {
    func fetchNFTSummary(owner: String) async throws -> NFTSummary {
        var page = 1
        var limit = 1000
        var pagesFetched = 0
        var totalCompressed = 0
        var totalUncompressed = 0
        var totalUnknown = 0
        var metadataFound = 0
        var editionsFound = 0
        var totalAssetsSeen = 0
        var excludedFungible = 0
        var countedNFT = 0
        var countedUnknown = 0
        var droppedOther = 0

        var reachedEnd = false
        while !reachedEnd {
            let pageResult: DASPageResult
            do {
                pageResult = try await fetchAssetsPage(owner: owner, page: page, limit: limit)
            } catch let error as SolanaRPCError {
                if case .rpcError(let message) = error,
                   limit > 100,
                   message.lowercased().contains("limit") {
                    // Fallback for providers/plans that reject larger DAS page limits.
                    limit = 100
                    page = 1
                    pagesFetched = 0
                    totalCompressed = 0
                    totalUncompressed = 0
                    totalUnknown = 0
                    metadataFound = 0
                    editionsFound = 0
                    totalAssetsSeen = 0
                    continue
                }
                throw error
            }

            pagesFetched += 1
            let items = pageResult.items
            totalAssetsSeen += items.count

            for item in items {
                if item.hasMetadata { metadataFound += 1 }
                if item.isEditionLike { editionsFound += 1 }

                if item.isFungibleLike {
                    excludedFungible += 1
                    continue
                }

                if item.isNFTLike {
                    countedNFT += 1
                    if item.compression?.compressed == true {
                        totalCompressed += 1
                    } else {
                        totalUncompressed += 1
                    }
                } else if item.isAmbiguousNFTLike {
                    countedUnknown += 1
                    totalUnknown += 1
                } else {
                    droppedOther += 1
                }
            }

#if DEBUG
            print("[NFT][DAS] wallet=\(owner) page=\(page) items=\(items.count) nft=\(countedNFT) unknown=\(countedUnknown) fungibleSkipped=\(excludedFungible) dropped=\(droppedOther) comp=\(totalCompressed) uncomp=\(totalUncompressed)")
#endif

            reachedEnd = items.count < limit
            page += 1
            if page > 100 {
                reachedEnd = true
            }
        }

        let total = totalCompressed + totalUncompressed
        return NFTSummary(
            totalCount: total,
            compressedCount: totalCompressed,
            uncompressedCount: totalUncompressed,
            unknownCount: totalUnknown,
            dataSource: .heliusDAS,
            debug: NFTSummaryDebug(
                candidates: total + totalUnknown,
                metadataFound: metadataFound,
                editionsFound: editionsFound,
                compressedFound: totalCompressed,
                pagesFetched: pagesFetched,
                pageLimit: limit,
                totalAssetsSeen: totalAssetsSeen,
                excludedFungible: excludedFungible,
                countedNFT: countedNFT,
                countedUnknown: countedUnknown,
                droppedOther: droppedOther
            )
        )
    }

    private func fetchAssetsPage(owner: String, page: Int, limit: Int) async throws -> DASPageResult {
        let payload = DASRequest(
            method: "getAssetsByOwner",
            params: DASParams(
                ownerAddress: owner,
                page: page,
                limit: limit,
                displayOptions: DASDisplayOptions(
                    showUnverifiedCollections: true,
                    showCollectionMetadata: true,
                    showFungible: false
                )
            )
        )
        let data = try JSONEncoder().encode(payload)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        request.timeoutInterval = 12

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SolanaRPCError.invalidResponse
        }

        let decoded: DASResponse
        do {
            decoded = try JSONDecoder().decode(DASResponse.self, from: responseData)
        } catch {
            await errorTracker.capture(
                category: "decoding_error",
                message: error.localizedDescription,
                httpStatus: http.statusCode,
                extra: ["service": "helius_das", "method": "getAssetsByOwner"]
            )
            throw error
        }

        if let rpcError = decoded.error {
            throw SolanaRPCError.rpcError(rpcError.message)
        }

        return DASPageResult(items: decoded.result?.items ?? [])
    }
}

private struct DASPageResult {
    let items: [DASAsset]
}

private struct DASRequest: Encodable {
    let jsonrpc = "2.0"
    let id = 1
    let method: String
    let params: DASParams
}

private struct DASParams: Encodable {
    let ownerAddress: String
    let page: Int
    let limit: Int
    let displayOptions: DASDisplayOptions?
}

private struct DASDisplayOptions: Encodable {
    let showUnverifiedCollections: Bool
    let showCollectionMetadata: Bool
    let showFungible: Bool

    enum CodingKeys: String, CodingKey {
        case showUnverifiedCollections
        case showCollectionMetadata
        case showFungible
    }
}

private struct DASResponse: Decodable {
    let result: DASResult?
    let error: DASErrorPayload?
}

private struct DASResult: Decodable {
    let items: [DASAsset]
}

private struct DASAsset: Decodable {
    let interface: String?
    let compression: DASCompression?
    let content: DASContent?
    let tokenInfo: DASTokenInfo?
    let grouping: [DASGrouping]?

    enum CodingKeys: String, CodingKey {
        case interface
        case compression
        case content
        case tokenInfo = "token_info"
        case grouping
    }

    private var normalizedInterface: String {
        (interface ?? "")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .uppercased()
    }

    var isFungibleLike: Bool {
        if normalizedInterface.contains("FUNGIBLE") && !normalizedInterface.contains("NFT") && !normalizedInterface.contains("NON_FUNGIBLE") {
            return true
        }
        if let decimals = decimals, decimals > 0 {
            return true
        }
        return false
    }

    var isNFTLike: Bool {
        let iface = normalizedInterface.lowercased()
        if iface.contains("nft") || iface.contains("programmablenft") || iface.contains("v1_nft") || iface.contains("legacynft") {
            return true
        }

        let tokenStandard = (content?.metadata?.tokenStandard ?? "").lowercased()
        if tokenStandard.contains("nonfungible") || tokenStandard.contains("programmable") {
            return true
        }

        if decimals == 0, balance == 1, (hasName || hasUri || hasGrouping || isCompressed) {
            return true
        }

        if isEditionLike, decimals == 0, balance == 1, (hasName || hasGrouping) {
            return true
        }

        return false
    }

    var isAmbiguousNFTLike: Bool {
        guard !isNFTLike && !isFungibleLike else { return false }
        return hasName || hasUri || hasGrouping || isCompressed
    }

    var hasMetadata: Bool {
        hasName || (content?.metadata?.symbol?.isEmpty == false)
    }

    var isEditionLike: Bool {
        if normalizedInterface.contains("PRINT") || normalizedInterface.contains("EDITION") {
            return true
        }
        let tokenStandard = (content?.metadata?.tokenStandard ?? "").lowercased()
        return tokenStandard.contains("print") || tokenStandard.contains("edition")
    }

    private var hasName: Bool {
        content?.metadata?.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var hasUri: Bool {
        let hasFiles = !(content?.files?.isEmpty ?? true)
        let hasJSONURI = content?.jsonURI?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        return hasFiles || hasJSONURI
    }

    private var hasGrouping: Bool {
        if content?.metadata?.collection != nil { return true }
        if !(content?.metadata?.creators?.isEmpty ?? true) { return true }
        return !(grouping?.isEmpty ?? true)
    }

    private var isCompressed: Bool {
        compression?.compressed == true
    }

    private var decimals: Int? {
        tokenInfo?.decimals
    }

    private var balance: Decimal? {
        guard let raw = tokenInfo?.balance else { return nil }
        return Decimal(string: raw)
    }
}

private struct DASCompression: Decodable {
    let compressed: Bool?
}

private struct DASContent: Decodable {
    let metadata: DASContentMetadata?
    let files: [DASFile]?
    let jsonURI: String?
    let links: DASLinks?

    enum CodingKeys: String, CodingKey {
        case metadata
        case files
        case jsonURI = "json_uri"
        case links
    }
}

private struct DASContentMetadata: Decodable {
    let name: String?
    let symbol: String?
    let tokenStandard: String?
    let collection: DASCollection?
    let creators: [DASCreator]?

    enum CodingKeys: String, CodingKey {
        case name
        case symbol
        case tokenStandard = "token_standard"
        case collection
        case creators
    }
}

private struct DASTokenInfo: Decodable {
    let balance: String?
    let decimals: Int?
}

private struct DASCollection: Decodable {
    let key: String?
}

private struct DASCreator: Decodable {
    let address: String?
}

private struct DASGrouping: Decodable {
    let groupKey: String?
    let groupValue: String?

    enum CodingKeys: String, CodingKey {
        case groupKey = "group_key"
        case groupValue = "group_value"
    }
}

private struct DASFile: Decodable {
    let uri: String?
}

private struct DASLinks: Decodable {
    let image: String?
}

private struct DASErrorPayload: Decodable {
    let code: Int
    let message: String
}
