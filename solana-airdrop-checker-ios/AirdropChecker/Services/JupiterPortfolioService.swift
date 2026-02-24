import Foundation

protocol JupiterPortfolioProviding {
    func setAPIKey(_ key: String?) async
    func fetchSnapshot(wallet: String) async throws -> JupiterPortfolioSnapshot
}

actor JupiterPortfolioService: JupiterPortfolioProviding {
    private let session: URLSession
    private let baseURL: URL
    private var apiKey: String?

    init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.jup.ag")!,
        apiKey: String? = nil
    ) {
        self.session = session
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    func setAPIKey(_ key: String?) {
        let normalized = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = (normalized?.isEmpty == false) ? normalized : nil
    }

    func fetchSnapshot(wallet: String) async throws -> JupiterPortfolioSnapshot {
        guard let apiKey, !apiKey.isEmpty else {
            throw JupiterPortfolioError.apiKeyMissing
        }

        async let positionsData = request(path: "/portfolio/v1/positions/\(wallet)", apiKey: apiKey)
        async let stakedData = request(path: "/portfolio/v1/staked-jup/\(wallet)", apiKey: apiKey)

        let (positionsRaw, stakedRaw) = try await (positionsData, stakedData)

        let positionsResponse = try decodePositionsResponse(from: positionsRaw)

        let stakedResponse = try? JSONDecoder().decode(JupiterStakedResponse.self, from: stakedRaw)
        let stakedJup = stakedResponse?.stakedAmount ?? 0

        let tokenDirectory = positionsResponse.tokenInfo ?? [:]

        var holdings: [JupiterHolding] = []
        var platformIDs = Set<String>()

        for element in positionsResponse.elements {
            if let platform = element.platformId {
                platformIDs.insert(platform)
            }
            guard let assets = element.data?.assets else { continue }

            for asset in assets {
                guard let mint = asset.data?.address, !mint.isEmpty else { continue }

                let metadata = resolveTokenInfo(tokenDirectory: tokenDirectory, networkId: asset.networkId, mint: mint)
                let symbol = metadata?.symbol ?? shortMint(mint)
                let name = metadata?.name ?? symbol
                let logoURL = metadata?.logoURI.flatMap(URL.init(string:))
                let amount = asset.data?.amount ?? 0
                let price = asset.data?.price
                let usdValue = asset.value ?? (price.map { amount * $0 } ?? 0)
                let tags = normalizeTags(metadata?.tags ?? [])

                holdings.append(
                    JupiterHolding(
                        mint: mint,
                        symbol: symbol,
                        name: name,
                        amount: amount,
                        usdValue: usdValue,
                        priceUSD: price,
                        logoURL: logoURL,
                        tags: tags
                    )
                )
            }
        }

        let uniqueHoldings = Dictionary(grouping: holdings, by: { $0.mint }).compactMap { _, sameMint in
            sameMint.max(by: { $0.usdValue < $1.usdValue })
        }
        .sorted { $0.usdValue > $1.usdValue }

        let computedNetWorth = uniqueHoldings.reduce(Decimal.zero) { $0 + $1.usdValue }
        let headerNetWorth = positionsResponse.elements
            .first(where: { ($0.label ?? "").lowercased().contains("net worth") })?
            .value
        let netWorth = headerNetWorth ?? (positionsResponse.totalValue ?? computedNetWorth)

        return JupiterPortfolioSnapshot(
            owner: positionsResponse.owner ?? wallet,
            fetchedAt: positionsResponse.date ?? Date(),
            netWorthUSD: netWorth,
            stakedJup: stakedJup,
            holdings: Array(uniqueHoldings.prefix(10)),
            platformCount: platformIDs.count
        )
    }

    private func request(path: String, apiKey: String) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw JupiterPortfolioError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw JupiterPortfolioError.invalidResponse
            }

            if http.statusCode == 401 || http.statusCode == 403 {
                throw JupiterPortfolioError.unauthorized
            }

            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw JupiterPortfolioError.transportError("Jupiter API error: \(body)")
            }

            return data
        } catch let error as JupiterPortfolioError {
            throw error
        } catch {
            throw JupiterPortfolioError.transportError(error.localizedDescription)
        }
    }

    private func decodePositionsResponse(from data: Data) throws -> JupiterPositionsResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(JupiterPositionsResponse.self, from: data) {
            return decoded
        }

        let fallbackDecoder = JSONDecoder()
        fallbackDecoder.dateDecodingStrategy = .secondsSince1970
        if let decoded = try? fallbackDecoder.decode(JupiterPositionsResponse.self, from: data) {
            return decoded
        }

        throw JupiterPortfolioError.invalidResponse
    }

    private func resolveTokenInfo(
        tokenDirectory: [String: [String: JupiterTokenInfo]],
        networkId: String?,
        mint: String
    ) -> JupiterTokenInfo? {
        if let networkId, let scoped = tokenDirectory[networkId]?[mint] {
            return scoped
        }
        if let global = tokenDirectory[""]?[mint] {
            return global
        }
        for (_, directory) in tokenDirectory {
            if let found = directory[mint] {
                return found
            }
        }
        return nil
    }

    private func shortMint(_ mint: String) -> String {
        guard mint.count > 10 else { return mint }
        return "\(mint.prefix(4))...\(mint.suffix(4))"
    }

    private func normalizeTags(_ tags: [String]) -> [String] {
        tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}

private struct JupiterPositionsResponse: Decodable {
    let date: Date?
    let owner: String?
    let elements: [JupiterPortfolioElement]
    let tokenInfo: [String: [String: JupiterTokenInfo]]?
    let totalValue: Decimal?
}

private struct JupiterPortfolioElement: Decodable {
    let type: String?
    let label: String?
    let platformId: String?
    let value: Decimal?
    let data: JupiterPortfolioElementData?
}

private struct JupiterPortfolioElementData: Decodable {
    let assets: [JupiterPortfolioAsset]?
}

private struct JupiterPortfolioAsset: Decodable {
    let networkId: String?
    let value: Decimal?
    let data: JupiterPortfolioAssetData?
}

private struct JupiterPortfolioAssetData: Decodable {
    let address: String?
    let amount: Decimal?
    let price: Decimal?
}

private struct JupiterTokenInfo: Decodable {
    let symbol: String?
    let name: String?
    let logoURI: String?
    let tags: [String]?
}

private struct JupiterStakedResponse: Decodable {
    let stakedAmount: Decimal
}
