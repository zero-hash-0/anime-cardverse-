import Foundation

struct WalletNFTCounts: Equatable {
    let standardNFTCount: Int
    let compressedNFTCount: Int

    var total: Int {
        standardNFTCount + compressedNFTCount
    }

    static let zero = WalletNFTCounts(standardNFTCount: 0, compressedNFTCount: 0)
}

protocol WalletNFTCounting {
    func fetchCounts(wallet: String) async throws -> WalletNFTCounts
}

protocol CompressedNFTCounting {
    func fetchCompressedNFTCount(owner: String) async throws -> Int
}

protocol NFTInventoryCounting {
    func fetchNFTCounts(owner: String) async throws -> WalletNFTCounts
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

    func fetchCounts(wallet: String) async throws -> WalletNFTCounts {
        if let inventoryProvider = compressedProvider as? NFTInventoryCounting {
            let counts = try await inventoryProvider.fetchNFTCounts(owner: wallet)
#if DEBUG
            print("[NFT] wallet=\(wallet) standard=\(counts.standardNFTCount) compressed=\(counts.compressedNFTCount) total=\(counts.total)")
#endif
            return counts
        }

        let candidateMints = try await rpcClient.fetchStandardNFTMintCandidates(owner: wallet)
        var standardCount = 0

        for mint in candidateMints {
            do {
                let supply = try await rpcClient.fetchTokenSupply(mint: mint)
                if supply.decimals == 0 && supply.amount == "1" {
                    standardCount += 1
                }
            } catch {
                // If supply lookup is unavailable, keep candidate based on amount=1/decimals=0 ownership heuristic.
                standardCount += 1
            }
        }

        var compressedCount = 0
        if let compressedProvider {
            do {
                compressedCount = try await compressedProvider.fetchCompressedNFTCount(owner: wallet)
            } catch {
                await errorTracker.capture(
                    category: "nft_counting_compressed_failed",
                    message: error.localizedDescription,
                    httpStatus: nil,
                    extra: ["wallet": wallet]
                )
            }
        }

        let counts = WalletNFTCounts(
            standardNFTCount: standardCount,
            compressedNFTCount: compressedCount
        )

        #if DEBUG
        print("[NFT] wallet=\(wallet) standard=\(counts.standardNFTCount) compressed=\(counts.compressedNFTCount) total=\(counts.total)")
        #endif
        return counts
    }
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
        let counts = try await fetchNFTCounts(owner: owner)
        return counts.compressedNFTCount
    }
}

extension HeliusCompressedNFTProvider: NFTInventoryCounting {
    func fetchNFTCounts(owner: String) async throws -> WalletNFTCounts {
        var page = 1
        let limit = 500
        var totalCompressed = 0
        var totalStandard = 0

        while true {
            let payload = DASRequest(
                method: "getAssetsByOwner",
                params: DASParams(
                    ownerAddress: owner,
                    page: page,
                    limit: limit
                )
            )
            let data = try JSONEncoder().encode(payload)
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            request.timeoutInterval = 10

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

            let items = decoded.result?.items ?? []
            for item in items where item.isNFTLike {
                if item.compression?.compressed == true {
                    totalCompressed += 1
                } else {
                    totalStandard += 1
                }
            }

            if items.count < limit {
                break
            }
            page += 1
            if page > 20 {
                break
            }
        }

        return WalletNFTCounts(standardNFTCount: totalStandard, compressedNFTCount: totalCompressed)
    }
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

    var isNFTLike: Bool {
        let interfaceKey = (interface ?? "").uppercased()
        let nftInterfaces = Set([
            "V1_NFT", "LEGACY_NFT", "V1_PRINT", "V2_NFT", "MPL_CORE_ASSET", "MPL_CORE_COLLECTION"
        ])

        if nftInterfaces.contains(interfaceKey) {
            return true
        }

        let tokenStandard = (content?.metadata?.tokenStandard ?? "").uppercased()
        if tokenStandard.contains("NONFUNGIBLE") {
            return true
        }

        if content?.metadata?.collection != nil {
            return true
        }

        return !(content?.metadata?.creators?.isEmpty ?? true)
    }
}

private struct DASCompression: Decodable {
    let compressed: Bool?
}

private struct DASContent: Decodable {
    let metadata: DASContentMetadata?
}

private struct DASContentMetadata: Decodable {
    let tokenStandard: String?
    let collection: DASCollection?
    let creators: [DASCreator]?

    enum CodingKeys: String, CodingKey {
        case tokenStandard = "token_standard"
        case collection
        case creators
    }
}

private struct DASCollection: Decodable {
    let key: String?
}

private struct DASCreator: Decodable {
    let address: String?
}

private struct DASErrorPayload: Decodable {
    let code: Int
    let message: String
}
