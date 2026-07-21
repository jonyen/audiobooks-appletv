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
}
