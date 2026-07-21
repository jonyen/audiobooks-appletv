import XCTest
@testable import AudiobooksCore

final class ChapterSplitterTests: XCTestCase {
    func testSplitsChapterHeadings() {
        let text = """
        CHAPTER I

        It is a truth universally acknowledged.

        CHAPTER II

        Mr. Bennet was among the earliest.
        """
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "CHAPTER I")
        XCTAssertTrue(chapters[0].body.contains("universally acknowledged"))
        XCTAssertEqual(chapters[1].title, "CHAPTER II")
    }

    func testSplitsBareRomanNumeralHeadings() {
        let text = "I.\n\nfirst body\n\nII.\n\nsecond body\n\nIII.\n\nthird body"
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[1].body, "second body")
    }

    func testSplitsStaveAndLetterHeadings() {
        let text = "STAVE ONE\n\nMarley was dead.\n\nSTAVE TWO\n\nThe Ghost."
        XCTAssertEqual(ChapterSplitter.split(text).count, 2)
    }

    func testRequiresBlankLineBeforeHeading() {
        // "II." inline in prose must not split.
        let text = "CHAPTER 1\n\nSee Act\nII. for details, and more prose here.\n\nCHAPTER 2\n\nbody"
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 2)
    }

    func testFallsBackToSingleChapter() {
        let text = "Just one blob of prose with no headings."
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].title, "Full Text")
        XCTAssertEqual(chapters[0].body, text)
    }

    func testHandlesCRLFLineEndings() {
        let text = "CHAPTER I\r\n\r\nfirst body\r\n\r\nCHAPTER II\r\n\r\nsecond body"
        let chapters = ChapterSplitter.split(text)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "CHAPTER I")
        XCTAssertEqual(chapters[1].body, "second body")
    }
}
