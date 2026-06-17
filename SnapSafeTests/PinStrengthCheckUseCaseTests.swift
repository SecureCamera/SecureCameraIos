//
//  PinStrengthCheckUseCaseTests.swift
//  SnapSafeTests
//

import XCTest
@testable import SnapSafe

final class PinStrengthCheckUseCaseTests: XCTestCase {

    private var sut: PinStrengthCheckUseCase!

    override func setUp() {
        sut = PinStrengthCheckUseCase()
    }

    // MARK: - Numeric tests (existing behaviour preserved)

    func test_numeric_validPin_isStrong() {
        XCTAssertTrue(sut.isPinStrongEnough("2847", isAlphanumeric: false))
        XCTAssertTrue(sut.isPinStrongEnough("739182", isAlphanumeric: false))
    }

    func test_numeric_tooShort_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("123", isAlphanumeric: false))
    }

    func test_numeric_allSameDigits_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("1111", isAlphanumeric: false))
        XCTAssertFalse(sut.isPinStrongEnough("999999", isAlphanumeric: false))
    }

    func test_numeric_ascendingSequence_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("1234", isAlphanumeric: false))
        XCTAssertFalse(sut.isPinStrongEnough("456789", isAlphanumeric: false))
    }

    func test_numeric_descendingSequence_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("9876", isAlphanumeric: false))
    }

    func test_numeric_blacklist_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("1212", isAlphanumeric: false))
        XCTAssertFalse(sut.isPinStrongEnough("6969", isAlphanumeric: false))
    }

    func test_numeric_containsLetters_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("12a4", isAlphanumeric: false))
    }

    // MARK: - Alphanumeric tests

    func test_alphanumeric_validMixed_isStrong() {
        XCTAssertTrue(sut.isPinStrongEnough("ab92", isAlphanumeric: true))
        XCTAssertTrue(sut.isPinStrongEnough("Tr0ub4", isAlphanumeric: true))
    }

    func test_alphanumeric_lettersOnly_isStrong() {
        XCTAssertTrue(sut.isPinStrongEnough("flux", isAlphanumeric: true))
    }

    func test_alphanumeric_tooShort_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("ab3", isAlphanumeric: true))
    }

    func test_alphanumeric_allSameChar_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("aaaa", isAlphanumeric: true))
        XCTAssertFalse(sut.isPinStrongEnough("1111", isAlphanumeric: true))
    }

    func test_alphanumeric_commonPassword_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("password", isAlphanumeric: true))
        XCTAssertFalse(sut.isPinStrongEnough("PASSWORD", isAlphanumeric: true))
        XCTAssertFalse(sut.isPinStrongEnough("letmein", isAlphanumeric: true))
        XCTAssertFalse(sut.isPinStrongEnough("abc123", isAlphanumeric: true))
        XCTAssertFalse(sut.isPinStrongEnough("qwerty", isAlphanumeric: true))
        XCTAssertFalse(sut.isPinStrongEnough("iloveyou", isAlphanumeric: true))
        XCTAssertFalse(sut.isPinStrongEnough("abcd1234", isAlphanumeric: true))
    }

    // MARK: - Default is numeric (isAlphanumeric: false)

    func test_defaultPinType_behavesAsNumeric() {
        XCTAssertTrue(sut.isPinStrongEnough("2847"))   // strong numeric
        XCTAssertFalse(sut.isPinStrongEnough("1234"))  // sequence
    }
}
