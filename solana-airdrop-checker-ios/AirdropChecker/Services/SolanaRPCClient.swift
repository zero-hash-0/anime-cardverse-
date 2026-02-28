import Foundation
import CryptoKit

protocol SolanaRPCFetching {
    func fetchTokenBalances(owner: String) async throws -> [TokenBalance]
    func getTokenAccountsByOwnerParsed(owner: String) async throws -> [SolanaParsedTokenAccount]
    func getMultipleAccounts(pubkeys: [String]) async throws -> [SolanaAccountLookupValue?]
    func getAccountInfo(pubkey: String) async throws -> SolanaAccountLookupValue?
    func fetchStandardNFTMintCandidates(owner: String) async throws -> [String]
    func fetchTokenSupply(mint: String) async throws -> TokenSupplyInfo
    func fetchNFTMetadataSummaries(mints: [String]) async throws -> [String: NFTMetadataSummary]
    func fetchNFTHoldings(owner: String) async throws -> NFTHoldingDiagnostics
}

enum SolanaRPCError: LocalizedError {
    case invalidResponse
    case rpcError(String)
    case timeout
    case unsupported

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Unexpected RPC response"
        case .rpcError(let message): return message
        case .timeout: return "RPC request timed out"
        case .unsupported: return "RPC method not supported by this provider"
        }
    }
}

struct TokenSupplyInfo: Equatable {
    let amount: String
    let decimals: Int
}

struct SolanaParsedTokenAccount: Equatable {
    let mint: String
    let amount: String
    let decimals: Int
}

struct SolanaAccountLookupValue: Equatable {
    let data: [String]?
}

struct NFTMetadataSummary: Equatable {
    let metadataExists: Bool
    let editionExists: Bool
}

struct NFTHolding: Equatable, Identifiable {
    let mint: String
    let metadataExists: Bool
    let editionExists: Bool
    let isCompressed: Bool
    let source: String

    var id: String { mint }
}

struct NFTHoldingDiagnostics: Equatable {
    let holdings: [NFTHolding]
    let candidates: Int
    let metadataFound: Int
    let editionsFound: Int
    let compressedFound: Int
}

final class SolanaRPCClient: SolanaRPCFetching {
    private static let defaultEndpoint = URL(string: "https://api.mainnet-beta.solana.com")
    private let rpcURL: URL
    private let session: URLSession
    private let errorTracker: ErrorTracking

    init(
        rpcEndpoint: String = "https://api.mainnet-beta.solana.com",
        session: URLSession = .shared,
        errorTracker: ErrorTracking = ErrorTrackerService.shared
    ) {
        self.rpcURL = URL(string: rpcEndpoint) ?? Self.defaultEndpoint ?? URL(fileURLWithPath: "/")
        self.session = session
        self.errorTracker = errorTracker
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

        request.timeoutInterval = 10

        let (data, response) = try await requestWithRetry(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let httpStatus = (response as? HTTPURLResponse)?.statusCode
            await errorTracker.capture(
                category: "api_non_200",
                message: "RPC non-200 response",
                httpStatus: httpStatus,
                extra: ["service": "solana_rpc"]
            )
            throw SolanaRPCError.invalidResponse
        }

        let decoded: RPCResponse
        do {
            decoded = try JSONDecoder().decode(RPCResponse.self, from: data)
        } catch {
            await errorTracker.capture(
                category: "decoding_error",
                message: error.localizedDescription,
                httpStatus: http.statusCode,
                extra: ["service": "solana_rpc"]
            )
            throw error
        }
        if let rpcError = decoded.error {
            await errorTracker.capture(
                category: "sync_pipeline_failure",
                message: rpcError.message,
                httpStatus: http.statusCode,
                extra: ["service": "solana_rpc", "code": String(rpcError.code)]
            )
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

    func fetchStandardNFTMintCandidates(owner: String) async throws -> [String] {
        let tokenProgram = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
        let token2022Program = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"

        async let tokenProgramCandidates = fetchNFTCandidates(owner: owner, programId: tokenProgram)
        async let token2022Candidates = fetchNFTCandidates(owner: owner, programId: token2022Program)

        let combined = try await tokenProgramCandidates + token2022Candidates
        return Array(Set(combined)).sorted()
    }

    func getTokenAccountsByOwnerParsed(owner: String) async throws -> [SolanaParsedTokenAccount] {
        let tokenProgram = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
        let token2022Program = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb"
        let programAccounts = try await fetchTokenAccounts(owner: owner, programId: tokenProgram)
        let token2022Accounts = try await fetchTokenAccounts(owner: owner, programId: token2022Program)

        return (programAccounts + token2022Accounts).compactMap { account in
            guard
                let info = account.account.data.parsed.info,
                let mint = info.mint,
                let tokenAmount = info.tokenAmount
            else {
                return nil
            }
            return SolanaParsedTokenAccount(
                mint: mint,
                amount: tokenAmount.amount,
                decimals: tokenAmount.decimals
            )
        }
    }

    func fetchTokenSupply(mint: String) async throws -> TokenSupplyInfo {
        let payload = RPCRequest(
            method: "getTokenSupply",
            params: [
                .string(mint)
            ]
        )

        let body = try JSONEncoder().encode(payload)
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 10

        let (data, response) = try await requestWithRetry(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SolanaRPCError.invalidResponse
        }

        let decoded: TokenSupplyRPCResponse
        do {
            decoded = try JSONDecoder().decode(TokenSupplyRPCResponse.self, from: data)
        } catch {
            await errorTracker.capture(
                category: "decoding_error",
                message: error.localizedDescription,
                httpStatus: http.statusCode,
                extra: ["service": "solana_rpc", "method": "getTokenSupply"]
            )
            throw error
        }

        if let rpcError = decoded.error {
            throw SolanaRPCError.rpcError(rpcError.message)
        }

        guard let value = decoded.result?.value else {
            throw SolanaRPCError.invalidResponse
        }

        return TokenSupplyInfo(amount: value.amount, decimals: value.decimals)
    }

    func fetchNFTMetadataSummaries(mints: [String]) async throws -> [String: NFTMetadataSummary] {
        guard !mints.isEmpty else { return [:] }

        let metadataProgram = "metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s"
        var metadataAddressToMint: [String: String] = [:]
        var editionAddressToMint: [String: String] = [:]
        var allAddresses: [String] = []

        for mint in mints {
            guard
                let metadataAddress = try? derivePDA(
                    seeds: ["metadata", metadataProgram, mint],
                    programId: metadataProgram
                ),
                let editionAddress = try? derivePDA(
                    seeds: ["metadata", metadataProgram, mint, "edition"],
                    programId: metadataProgram
                )
            else {
                continue
            }
            metadataAddressToMint[metadataAddress] = mint
            editionAddressToMint[editionAddress] = mint
            allAddresses.append(metadataAddress)
            allAddresses.append(editionAddress)
        }

        guard !allAddresses.isEmpty else { return [:] }

        var metadataByMint: [String: Bool] = [:]
        var editionByMint: [String: Bool] = [:]
        let batchSize = 100

        var offset = 0
        while offset < allAddresses.count {
            let end = min(offset + batchSize, allAddresses.count)
            let chunk = Array(allAddresses[offset..<end])
            let values = try await fetchMultipleAccounts(addresses: chunk)
            for (address, account) in zip(chunk, values) {
                if let mint = metadataAddressToMint[address] {
                    metadataByMint[mint] = metadataByMint[mint] == true || isValidMetadataAccount(account)
                }
                if let mint = editionAddressToMint[address] {
                    editionByMint[mint] = editionByMint[mint] == true || account != nil
                }
            }
            offset = end
        }

        var summaries: [String: NFTMetadataSummary] = [:]
        for mint in mints {
            summaries[mint] = NFTMetadataSummary(
                metadataExists: metadataByMint[mint] ?? false,
                editionExists: editionByMint[mint] ?? false
            )
        }
        return summaries
    }

    func fetchNFTHoldings(owner: String) async throws -> NFTHoldingDiagnostics {
        let candidates = try await fetchStandardNFTMintCandidates(owner: owner)
        let summaries = try await fetchNFTMetadataSummaries(mints: candidates)

        var holdings: [NFTHolding] = []
        var metadataFound = 0
        var editionsFound = 0

        for mint in candidates {
            let summary = summaries[mint] ?? NFTMetadataSummary(metadataExists: false, editionExists: false)
            if summary.metadataExists { metadataFound += 1 }
            if summary.editionExists { editionsFound += 1 }

            if summary.metadataExists || summary.editionExists {
                holdings.append(
                    NFTHolding(
                        mint: mint,
                        metadataExists: summary.metadataExists,
                        editionExists: summary.editionExists,
                        isCompressed: false,
                        source: "rpc"
                    )
                )
            }
        }

        // If metadata accounts are unavailable on this RPC, fall back to deterministic ownership heuristic.
        if holdings.isEmpty && !candidates.isEmpty {
            for mint in candidates {
                holdings.append(
                    NFTHolding(
                        mint: mint,
                        metadataExists: false,
                        editionExists: false,
                        isCompressed: false,
                        source: "rpc_heuristic"
                    )
                )
            }
        }

        return NFTHoldingDiagnostics(
            holdings: holdings,
            candidates: candidates.count,
            metadataFound: metadataFound,
            editionsFound: editionsFound,
            compressedFound: 0
        )
    }

    func getMultipleAccounts(pubkeys: [String]) async throws -> [SolanaAccountLookupValue?] {
        try await fetchMultipleAccounts(addresses: pubkeys).map { raw in
            raw.map { SolanaAccountLookupValue(data: $0.data) }
        }
    }

    func getAccountInfo(pubkey: String) async throws -> SolanaAccountLookupValue? {
        let accounts = try await getMultipleAccounts(pubkeys: [pubkey])
        return accounts.first ?? nil
    }

    private func fetchNFTCandidates(owner: String, programId: String) async throws -> [String] {
        let tokenAccounts = try await fetchTokenAccounts(owner: owner, programId: programId)
        return tokenAccounts.compactMap { account -> String? in
            guard
                let info = account.account.data.parsed.info,
                let mint = info.mint,
                let tokenAmount = info.tokenAmount,
                tokenAmount.amount == "1",
                tokenAmount.decimals == 0
            else {
                return nil
            }
            return mint
        }
    }

    private func fetchTokenAccounts(owner: String, programId: String) async throws -> [TokenAccount] {
        let payload = RPCRequest(
            method: "getTokenAccountsByOwner",
            params: [
                .string(owner),
                .object(["programId": .string(programId)]),
                .object(["encoding": .string("jsonParsed")])
            ]
        )

        let body = try JSONEncoder().encode(payload)
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 10

        let (data, response) = try await requestWithRetry(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SolanaRPCError.invalidResponse
        }

        let decoded: RPCResponse
        do {
            decoded = try JSONDecoder().decode(RPCResponse.self, from: data)
        } catch {
            await errorTracker.capture(
                category: "decoding_error",
                message: error.localizedDescription,
                httpStatus: http.statusCode,
                extra: ["service": "solana_rpc", "method": "getTokenAccountsByOwner"]
            )
            throw error
        }

        if let rpcError = decoded.error {
            throw SolanaRPCError.rpcError(rpcError.message)
        }

        return decoded.result?.value ?? []
    }

    private func requestWithRetry(_ request: URLRequest, maxAttempts: Int = 3) async throws -> (Data, URLResponse) {
        var attempt = 0
        var delayNs: UInt64 = 300_000_000
        var lastError: Error = SolanaRPCError.invalidResponse

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

        if let urlError = lastError as? URLError, urlError.code == .timedOut {
            await errorTracker.capture(
                category: "network_timeout",
                message: urlError.localizedDescription,
                httpStatus: nil,
                extra: ["service": "solana_rpc"]
            )
            throw SolanaRPCError.timeout
        }
        await errorTracker.capture(
            category: "network_error",
            message: lastError.localizedDescription,
            httpStatus: nil,
            extra: ["service": "solana_rpc"]
        )
        throw lastError
    }

    private func fetchMultipleAccounts(addresses: [String]) async throws -> [RPCMultipleAccountValue?] {
        let payload = RPCRequest(
            method: "getMultipleAccounts",
            params: [
                .array(addresses.map { .string($0) }),
                .object(["encoding": .string("base64")])
            ]
        )
        let body = try JSONEncoder().encode(payload)
        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 10

        let (data, response) = try await requestWithRetry(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw SolanaRPCError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(RPCMultipleAccountsResponse.self, from: data)
        if let rpcError = decoded.error {
            throw SolanaRPCError.rpcError(rpcError.message)
        }
        return decoded.result?.value ?? []
    }

    private func isValidMetadataAccount(_ account: RPCMultipleAccountValue?) -> Bool {
        guard let dataArray = account?.data, let encoded = dataArray.first else { return false }
        guard let data = Data(base64Encoded: encoded) else { return false }
        guard data.count > 65 else { return false }
        var cursor = 1 + 32 + 32 // key + update authority + mint
        guard let name = readBorshString(from: data, cursor: &cursor),
              let _ = readBorshString(from: data, cursor: &cursor),
              let uri = readBorshString(from: data, cursor: &cursor)
        else { return false }
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            uri.lowercased().hasPrefix("http")
    }

    private func readBorshString(from data: Data, cursor: inout Int) -> String? {
        guard cursor + 4 <= data.count else { return nil }
        let lengthData = data[cursor..<(cursor + 4)]
        cursor += 4
        let length = Int(UInt32(littleEndian: lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }))
        guard length >= 0, cursor + length <= data.count else { return nil }
        let raw = data[cursor..<(cursor + length)]
        cursor += length
        return String(data: raw, encoding: .utf8)?
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func derivePDA(seeds: [String], programId: String) throws -> String {
        let programData = try Base58.decode(programId)
        for bump in stride(from: 255, through: 0, by: -1) {
            var hasher = SHA256()
            for seed in seeds {
                hasher.update(data: Data(seed.utf8))
            }
            hasher.update(data: Data([UInt8(bump)]))
            hasher.update(data: programData)
            hasher.update(data: Data("ProgramDerivedAddress".utf8))
            let digest = Data(hasher.finalize())
            if !isOnCurve(publicKey: digest) {
                return Base58.encode(digest)
            }
        }
        throw SolanaRPCError.invalidResponse
    }

    private func isOnCurve(publicKey: Data) -> Bool {
        guard publicKey.count == 32 else { return false }
        return (try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey)) != nil
    }

    private func decimalPowerOfTen(_ exponent: Int) -> Decimal {
        guard exponent > 0 else { return 1 }
        return (0..<exponent).reduce(Decimal(1)) { partial, _ in partial * 10 }
    }
}

extension SolanaRPCFetching {
    func getTokenAccountsByOwnerParsed(owner: String) async throws -> [SolanaParsedTokenAccount] {
        throw SolanaRPCError.unsupported
    }

    func getMultipleAccounts(pubkeys: [String]) async throws -> [SolanaAccountLookupValue?] {
        throw SolanaRPCError.unsupported
    }

    func getAccountInfo(pubkey: String) async throws -> SolanaAccountLookupValue? {
        throw SolanaRPCError.unsupported
    }

    func fetchStandardNFTMintCandidates(owner: String) async throws -> [String] {
        throw SolanaRPCError.unsupported
    }

    func fetchTokenSupply(mint: String) async throws -> TokenSupplyInfo {
        throw SolanaRPCError.unsupported
    }

    func fetchNFTMetadataSummaries(mints: [String]) async throws -> [String: NFTMetadataSummary] {
        throw SolanaRPCError.unsupported
    }

    func fetchNFTHoldings(owner: String) async throws -> NFTHoldingDiagnostics {
        throw SolanaRPCError.unsupported
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
    case array([RPCParam])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .object(let dictionary):
            try container.encode(dictionary)
        case .array(let values):
            try container.encode(values)
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

private struct RPCMultipleAccountsResponse: Codable {
    let result: RPCMultipleAccountsResult?
    let error: RPCErrorPayload?
}

private struct RPCMultipleAccountsResult: Codable {
    let value: [RPCMultipleAccountValue?]
}

private struct RPCMultipleAccountValue: Codable {
    let data: [String]?
}

private struct TokenSupplyRPCResponse: Codable {
    let result: TokenSupplyRPCResult?
    let error: RPCErrorPayload?
}

private struct TokenSupplyRPCResult: Codable {
    let value: TokenSupplyValue
}

private struct TokenSupplyValue: Codable {
    let amount: String
    let decimals: Int
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

private enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    private static let map: [Character: Int] = {
        var dictionary: [Character: Int] = [:]
        for (index, char) in alphabet.enumerated() {
            dictionary[char] = index
        }
        return dictionary
    }()

    static func decode(_ string: String) throws -> Data {
        guard !string.isEmpty else { return Data() }
        var bytes = [UInt8](repeating: 0, count: 1)
        for char in string {
            guard let value = map[char] else { throw SolanaRPCError.invalidResponse }
            var carry = value
            for i in 0..<bytes.count {
                let idx = bytes.count - 1 - i
                let x = Int(bytes[idx]) * 58 + carry
                bytes[idx] = UInt8(x & 0xff)
                carry = x >> 8
            }
            while carry > 0 {
                bytes.insert(UInt8(carry & 0xff), at: 0)
                carry >>= 8
            }
        }

        var leadingZeros = 0
        for char in string where char == "1" {
            leadingZeros += 1
        }
        return Data(repeating: 0, count: leadingZeros) + Data(bytes.drop { $0 == 0 })
    }

    static func encode(_ data: Data) -> String {
        guard !data.isEmpty else { return "" }
        var bytes = [UInt8](data)
        var result = ""
        while !bytes.isEmpty && bytes.contains(where: { $0 != 0 }) {
            var quotient: [UInt8] = []
            var remainder = 0
            for byte in bytes {
                let accumulator = Int(byte) + remainder * 256
                let digit = accumulator / 58
                remainder = accumulator % 58
                if !quotient.isEmpty || digit != 0 {
                    quotient.append(UInt8(digit))
                }
            }
            result.insert(alphabet[remainder], at: result.startIndex)
            bytes = quotient
        }
        for byte in data where byte == 0 {
            _ = byte
            result.insert("1", at: result.startIndex)
        }
        return result
    }
}
