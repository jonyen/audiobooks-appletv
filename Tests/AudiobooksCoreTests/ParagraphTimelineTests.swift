import XCTest
@testable import AudiobooksCore

final class ParagraphTimelineTests: XCTestCase {

    // MARK: Splitting

    func testSplitsOnBlankLines() {
        let body = "First paragraph\nstill first.\n\nSecond paragraph."
        XCTAssertEqual(
            ParagraphTimeline.paragraphs(from: body),
            ["First paragraph\nstill first.", "Second paragraph."]
        )
    }

    func testSplittingHandlesCRLFAndWhitespaceOnlyBlankLines() {
        let body = "One.\r\n \r\nTwo.\r\n\r\n\r\nThree."
        XCTAssertEqual(
            ParagraphTimeline.paragraphs(from: body),
            ["One.", "Two.", "Three."]
        )
    }

    func testSplittingDropsEmptyAndTrimsWhitespace() {
        let body = "\n\n  Alpha.  \n\n\n"
        XCTAssertEqual(ParagraphTimeline.paragraphs(from: body), ["Alpha."])
    }

    // MARK: Timeline

    func testStartsProportionalToCharacterCounts() {
        // 10 chars then 30 chars over 40s: starts at 0 and 10.
        let timeline = ParagraphTimeline(
            paragraphs: [String(repeating: "a", count: 10),
                         String(repeating: "b", count: 30)],
            duration: 40
        )
        XCTAssertEqual(timeline?.paragraphIndex(at: 0), 0)
        XCTAssertEqual(timeline?.paragraphIndex(at: 9.9), 0)
        XCTAssertEqual(timeline?.paragraphIndex(at: 10.1), 1)
        XCTAssertEqual(timeline?.paragraphIndex(at: 39), 1)
    }

    func testClampsOutsideDuration() {
        let timeline = ParagraphTimeline(paragraphs: ["aaa", "bbb"], duration: 10)
        XCTAssertEqual(timeline?.paragraphIndex(at: -5), 0)
        XCTAssertEqual(timeline?.paragraphIndex(at: 99), 1)
    }

    func testNilForEmptyParagraphsOrBadDuration() {
        XCTAssertNil(ParagraphTimeline(paragraphs: [], duration: 10))
        XCTAssertNil(ParagraphTimeline(paragraphs: ["a"], duration: 0))
        XCTAssertNil(ParagraphTimeline(paragraphs: ["a"], duration: .infinity))
    }

    func testLeadInShiftsAllStarts() {
        // leadIn 10 over 40s, paragraphs 10 and 30 chars:
        // paragraph 0 spans 10..17.5, paragraph 1 spans 17.5..40.
        let timeline = ParagraphTimeline(
            paragraphs: [String(repeating: "a", count: 10),
                         String(repeating: "b", count: 30)],
            duration: 40, leadIn: 10
        )
        XCTAssertEqual(timeline?.paragraphIndex(at: 12), 0)
        XCTAssertEqual(timeline?.paragraphIndex(at: 18), 1)
    }

    func testPositionsBeforeLeadInClampToFirstParagraph() {
        let timeline = ParagraphTimeline(paragraphs: ["aaa", "bbb"], duration: 40, leadIn: 10)
        XCTAssertEqual(timeline?.paragraphIndex(at: 0), 0)
        XCTAssertEqual(timeline?.paragraphIndex(at: 9.9), 0)
    }

    func testLeadInClampsToHalfDurationAndNegativeToZero() {
        // leadIn 30 of 40s clamps to 20: position 19 is still before paragraph 0.
        let clamped = ParagraphTimeline(paragraphs: ["aaa", "bbb"], duration: 40, leadIn: 30)
        XCTAssertEqual(clamped?.paragraphIndex(at: 19), 0)
        XCTAssertEqual(clamped?.paragraphIndex(at: 31), 1)
        // Negative leadIn behaves as 0.
        let negative = ParagraphTimeline(paragraphs: ["aaa", "bbb"], duration: 10, leadIn: -5)
        XCTAssertEqual(negative?.paragraphIndex(at: 6), 1)
    }
}
