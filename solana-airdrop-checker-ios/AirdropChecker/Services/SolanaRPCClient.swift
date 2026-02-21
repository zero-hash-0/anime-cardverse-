import Foundation

protocol SolanaRPCFetching {
    func fetchTokenBalances(owner: String) async throws -> [TokenBalance]
}

enum SolanaRPCError: LocalizedError {
    case invalidResponse
    case rpcError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Unexpected RPC response"
        case .rpcError(let message): return message
        }
    }
}

final class SolanaRPCClient: SolanaRPCFetching {
    private let rpcURL: URL
    private let session: URLSession

    init(rpcEndpoint: String = "https://api.mainnet-beta.solana.com", session: URLSession = .shared) {
        self.rpcURL = URL(string: rpcEndpoint) ?? URL(string: "https://api.mainnet-beta.solana.com")!
        self.session = session
    }

    func fetchTokenBalances(owner: String) async throws -> [TokenBalance] {
        let payload = RPCRequest(
            method: "getTokenAccountsByOwner",
            params: [
                .string(owner),
                .object(["programId": .string("TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA")]),
                .object(["encoding": .string("jsonParsed")])
            ]
        )

        let body = try JSONEncoder().encode(payload)
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SolanaRPCError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(RPCResponse.self, from: data)
        if let rpcError = decoded.error {
            throw SolanaRPCError.rpcError(rpcError.message)
        }

        return decoded.result?.value.compactMap { account in
            guard
                let info = account.account.data.parsed.info,
                let mint = info.mint,
                let tokenAmount = info.tokenAmount,
                let amountRaw = Decimal(string: tokenAmount.amount)
            else {
                return nil
            }

            let divisor = decimalPowerOfTen(tokenAmount.decimals)
            let normalized = amountRaw / divisor
            return TokenBalance(mint: mint, amount: normalized)
        } ?? []
    }

    private func decimalPowerOfTen(_ exponent: Int) -> Decimal {
        guard exponent > 0 else { return 1 }
        return (0..<exponent).reduce(Decimal(1)) { partial, _ in partial * 10 }
    }
}

private struct RPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id = 1
    let method: String
    let params: [RPCParam]
}

private enum RPCParam: Codable {
    case string(String)
    case object([String: RPCParam])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .object(let dictionary):
            try container.encode(dictionary)
        }
    }
}

private struct RPCResponse: Codable {
    let result: RPCResult?
    let error: RPCErrorPayload?
}

private struct RPCErrorPayload: Codable {
    let code: Int
    let message: String
}

private struct RPCResult: Codable {
    let value: [TokenAccount]
}

private struct TokenAccount: Codable {
    let account: TokenAccountData
}

private struct TokenAccountData: Codable {
    let data: ParsedData
}

private struct ParsedData: Codable {
    let parsed: ParsedInner
}

private struct ParsedInner: Codable {
    let info: TokenInfo?
}

private struct TokenInfo: Codable {
    let mint: String?
    let tokenAmount: TokenAmount?
}

private struct TokenAmount: Codable {
    let amount: String
    let decimals: Int
}
