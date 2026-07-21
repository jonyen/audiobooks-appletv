import XCTest
@testable import AudiobooksCore

final class RomanNumeralsTests: XCTestCase {
    func testParsesBasicNumerals() {
        XCTAssertEqual(RomanNumerals.parse("I"), 1)
        XCTAssertEqual(RomanNumerals.parse("IV"), 4)
        XCTAssertEqual(RomanNumerals.parse("IX"), 9)
        XCTAssertEqual(RomanNumerals.parse("XIX"), 19)
        XCTAssertEqual(RomanNumerals.parse("XLII"), 42)
        XCTAssertEqual(RomanNumerals.parse("MCMXCIV"), 1994)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(RomanNumerals.parse("xii"), 12)
    }

    func testRejectsInvalid() {
        XCTAssertNil(RomanNumerals.parse(""))
        XCTAssertNil(RomanNumerals.parse("ABC"))
        XCTAssertNil(RomanNumerals.parse("IL"))
        XCTAssertNil(RomanNumerals.parse("chapter"))
    }
}
