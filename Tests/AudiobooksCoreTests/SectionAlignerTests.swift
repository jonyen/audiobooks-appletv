import XCTest
@testable import AudiobooksCore

final class SectionAlignerTests: XCTestCase {
    func testNormalizeConvertsRomansAndStripsPunctuation() {
        XCTAssertEqual(SectionAligner.normalize("CHAPTER IV."), "chapter 4")
        XCTAssertEqual(SectionAligner.normalize("Chapter 04 — The Sea"), "chapter 4 the sea")
        XCTAssertEqual(SectionAligner.normalize("\"Stave One\""), "stave one")
    }

    func testExactMatch() {
        let alignment = SectionAligner.align(
            sectionTitles: ["Chapter I", "Chapter II"],
            chapterTitles: ["CHAPTER 1", "CHAPTER 2"]
        )
        XCTAssertEqual(alignment.chapterIndexBySection, [0, 1])
        XCTAssertEqual(alignment.matchedCount, 2)
    }

    func testContainmentDoesNotConfusePrefixNumbers() {
        // Section "Chapter 12" must not match chapter "CHAPTER 1".
        let alignment = SectionAligner.align(
            sectionTitles: ["12 - Chapter 12"],
            chapterTitles: ["CHAPTER 1", "CHAPTER 12"]
        )
        XCTAssertEqual(alignment.chapterIndexBySection, [1])
    }

    func testUnmatchedSectionIsNil() {
        let alignment = SectionAligner.align(
            sectionTitles: ["Translator's Preface", "Chapter 1"],
            chapterTitles: ["CHAPTER 1", "CHAPTER 2"]
        )
        XCTAssertEqual(alignment.chapterIndexBySection, [nil, 0])
        XCTAssertEqual(alignment.matchedCount, 1)
    }

    func testPositionalFallbackWhenCountsEqualAndNothingMatched() {
        let alignment = SectionAligner.align(
            sectionTitles: ["Part the First", "Part the Second"],
            chapterTitles: ["The Beginning", "The End"]
        )
        XCTAssertEqual(alignment.chapterIndexBySection, [0, 1])
    }

    func testTOCStubsDoNotWinAlignment() {
        let longBody = String(repeating: "prose ", count: 100)
        let alignment = SectionAligner.align(
            sectionTitles: ["Chapter 1", "Chapter 2"],
            chapterTitles: ["CHAPTER I.", "CHAPTER II.", "CHAPTER I.", "CHAPTER II."],
            chapterBodies: ["", "", longBody, longBody]
        )
        XCTAssertEqual(alignment.chapterIndexBySection, [2, 3])
    }

    func testBodiesOmittedKeepsOldBehavior() {
        let alignment = SectionAligner.align(
            sectionTitles: ["Chapter I"],
            chapterTitles: ["CHAPTER 1"]
        )
        XCTAssertEqual(alignment.chapterIndexBySection, [0])
    }
}
