import XCTest
@testable import AirdropChecker

final class AddressValidatorTests: XCTestCase {
    func testValidAddressPasses() {
        let valid = "2wP9fbbQ4P4Yx8Lw2fT2N5zM8eVxW4xM5J2gCwK9Ts3N"
        XCTAssertTrue(AddressValidator.isLikelySolanaAddress(valid))
    }

    func testInvalidCharactersFail() {
        let invalid = "2wP9fbbQ4P4Yx8Lw2fT2N5zM8eVxW4xM5J2gCwK9Ts0O"
        XCTAssertFalse(AddressValidator.isLikelySolanaAddress(invalid))
    }

    func testInvalidLengthFails() {
        XCTAssertFalse(AddressValidator.isLikelySolanaAddress("short"))
    }
}
