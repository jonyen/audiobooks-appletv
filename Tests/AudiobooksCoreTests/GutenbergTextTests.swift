import XCTest
@testable import AudiobooksCore

final class GutenbergTextTests: XCTestCase {
    func testExtractsIDFromCommonURLShapes() {
        XCTAssertEqual(GutenbergText.ebookID(fromTextSource: "http://www.gutenberg.org/etext/1342"), 1342)
        XCTAssertEqual(GutenbergText.ebookID(fromTextSource: "https://www.gutenberg.org/ebooks/158"), 158)
        XCTAssertEqual(GutenbergText.ebookID(fromTextSource: "https://www.gutenberg.org/files/76/76-h/76-h.htm"), 76)
        XCTAssertEqual(GutenbergText.ebookID(fromTextSource: "https://www.gutenberg.org/cache/epub/2701/pg2701.txt"), 2701)
    }

    func testRejectsNonGutenbergSources() {
        XCTAssertNil(GutenbergText.ebookID(fromTextSource: "https://en.wikisource.org/wiki/Some_Book"))
        XCTAssertNil(GutenbergText.ebookID(fromTextSource: ""))
    }

    func testStripsBoilerplate() {
        let raw = """
        The Project Gutenberg eBook of Example
        junk license header

        *** START OF THE PROJECT GUTENBERG EBOOK EXAMPLE ***

        CHAPTER I

        Actual content here.

        *** END OF THE PROJECT GUTENBERG EBOOK EXAMPLE ***
        more license junk
        """
        let stripped = GutenbergText.stripBoilerplate(raw)
        XCTAssertTrue(stripped.hasPrefix("CHAPTER I"))
        XCTAssertTrue(stripped.hasSuffix("Actual content here."))
        XCTAssertFalse(stripped.contains("license"))
    }

    func testStripHandlesThisVariantAndMissingMarkers() {
        let variant = "*** START OF THIS PROJECT GUTENBERG EBOOK X ***\nbody\n*** END OF THIS PROJECT GUTENBERG EBOOK X ***"
        XCTAssertEqual(GutenbergText.stripBoilerplate(variant), "body")
        XCTAssertEqual(GutenbergText.stripBoilerplate("no markers at all"), "no markers at all")
    }

    func testStripsBoilerplateWithCRLF() {
        let raw = "header junk\r\n*** START OF THE PROJECT GUTENBERG EBOOK JANE EYRE ***\r\n\r\nCHAPTER I\r\n\r\nThere was no possibility.\r\n\r\n*** END OF THE PROJECT GUTENBERG EBOOK JANE EYRE ***\r\nfooter junk"
        let stripped = GutenbergText.stripBoilerplate(raw)
        XCTAssertTrue(stripped.hasPrefix("CHAPTER I"), "got: \(stripped.prefix(40))")
        XCTAssertTrue(stripped.hasSuffix("There was no possibility."))
        XCTAssertFalse(stripped.contains("footer"))
    }
}
