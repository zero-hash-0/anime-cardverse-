import Foundation

enum AddressValidator {
    private static let base58 = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")

    static func isLikelySolanaAddress(_ value: String) -> Bool {
        guard (32...44).contains(value.count) else { return false }
        return value.unicodeScalars.allSatisfy(base58.contains)
    }
}
