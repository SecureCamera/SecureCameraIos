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
        XCTAssertTrue(sut.isPinStrongEnough("2847", pinType: .numeric))
        XCTAssertTrue(sut.isPinStrongEnough("739182", pinType: .numeric))
    }

    func test_numeric_tooShort_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("123", pinType: .numeric))
    }

    func test_numeric_allSameDigits_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("1111", pinType: .numeric))
        XCTAssertFalse(sut.isPinStrongEnough("999999", pinType: .numeric))
    }

    func test_numeric_ascendingSequence_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("1234", pinType: .numeric))
        XCTAssertFalse(sut.isPinStrongEnough("456789", pinType: .numeric))
    }

    func test_numeric_descendingSequence_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("9876", pinType: .numeric))
    }

    func test_numeric_blacklist_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("1212", pinType: .numeric))
        XCTAssertFalse(sut.isPinStrongEnough("6969", pinType: .numeric))
    }

    func test_numeric_containsLetters_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("12a4", pinType: .numeric))
    }

    // MARK: - Alphanumeric tests

    func test_alphanumeric_validMixed_isStrong() {
        XCTAssertTrue(sut.isPinStrongEnough("ab92", pinType: .alphanumeric))
        XCTAssertTrue(sut.isPinStrongEnough("Tr0ub4", pinType: .alphanumeric))
    }

    func test_alphanumeric_lettersOnly_isStrong() {
        XCTAssertTrue(sut.isPinStrongEnough("flux", pinType: .alphanumeric))
    }

    func test_alphanumeric_tooShort_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("ab3", pinType: .alphanumeric))
    }

    func test_alphanumeric_allSameChar_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("aaaa", pinType: .alphanumeric))
        XCTAssertFalse(sut.isPinStrongEnough("1111", pinType: .alphanumeric))
    }

    func test_alphanumeric_commonPassword_isWeak() {
        XCTAssertFalse(sut.isPinStrongEnough("password", pinType: .alphanumeric))
        XCTAssertFalse(sut.isPinStrongEnough("PASSWORD", pinType: .alphanumeric))
        XCTAssertFalse(sut.isPinStrongEnough("letmein", pinType: .alphanumeric))
        XCTAssertFalse(sut.isPinStrongEnough("abc123", pinType: .alphanumeric))
        XCTAssertFalse(sut.isPinStrongEnough("qwerty", pinType: .alphanumeric))
        XCTAssertFalse(sut.isPinStrongEnough("iloveyou", pinType: .alphanumeric))
        XCTAssertFalse(sut.isPinStrongEnough("abcd1234", pinType: .alphanumeric))
    }

    // MARK: - Default pinType is numeric

    func test_defaultPinType_behavesAsNumeric() {
        XCTAssertTrue(sut.isPinStrongEnough("2847"))   // strong numeric
        XCTAssertFalse(sut.isPinStrongEnough("1234"))  // sequence
    }
}
