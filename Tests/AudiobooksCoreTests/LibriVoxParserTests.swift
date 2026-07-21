import XCTest
@testable import AudiobooksCore

final class LibriVoxParserTests: XCTestCase {
    let fixture = """
    {"books":[{
        "id":"52",
        "title":"Pride and Prejudice",
        "description":"<p>A classic novel.</p>",
        "url_text_source":"http://www.gutenberg.org/etext/1342",
        "language":"English",
        "copyright_year":"1813",
        "num_sections":"61",
        "url_iarchive":"http://www.archive.org/details/pride_prejudice_librivox",
        "coverart_jpg":"https://ia800207.us.archive.org/cover.jpg",
        "totaltime":"11:35:59",
        "totaltimesecs":41759,
        "authors":[{"id":"31","first_name":"Jane","last_name":"Austen"}],
        "genres":[{"id":"1","name":"General Fiction"}],
        "sections":[
            {"id":"100","section_number":"1","title":"Chapter 1",
             "listen_url":"https://ia800207.us.archive.org/pp_01.mp3","playtime":"1626"},
            {"id":"101","section_number":"2","title":"Chapter 2",
             "listen_url":"https://ia800207.us.archive.org/pp_02.mp3","playtime":"1417"}
        ]
    },{
        "id":"99",
        "title":"No Text Book",
        "description":"",
        "url_text_source":null,
        "num_sections":"1",
        "url_iarchive":"http://www.archive.org/details/notext_librivox",
        "coverart_jpg":null,
        "totaltimesecs":100,
        "authors":[],
        "genres":[],
        "sections":[]
    }]}
    """.data(using: .utf8)!

    func testParsesBooksWithStringNumerics() throws {
        let books = try LibriVoxParser.parseBooks(fixture)
        XCTAssertEqual(books.count, 2)
        let pride = books[0]
        XCTAssertEqual(pride.id, 52)
        XCTAssertEqual(pride.title, "Pride and Prejudice")
        XCTAssertEqual(pride.authors, "Jane Austen")
        XCTAssertEqual(pride.description, "A classic novel.")
        XCTAssertEqual(pride.genres, ["General Fiction"])
        XCTAssertEqual(pride.totalTimeSeconds, 41759)
        XCTAssertEqual(pride.sections.count, 2)
        XCTAssertEqual(pride.sections[1].playtimeSeconds, 1417)
        XCTAssertEqual(pride.sections[0].listenURL.absoluteString, "https://ia800207.us.archive.org/pp_01.mp3")
    }

    func testTextAvailability() throws {
        let books = try LibriVoxParser.parseBooks(fixture)
        XCTAssertEqual(books[0].gutenbergID, 1342)
        XCTAssertTrue(books[0].hasText)
        XCTAssertNil(books[1].gutenbergID)
        XCTAssertFalse(books[1].hasText)
    }

    func testCoverFallbackToArchiveIdentifier() throws {
        let books = try LibriVoxParser.parseBooks(fixture)
        XCTAssertEqual(books[0].coverURL?.absoluteString, "https://ia800207.us.archive.org/cover.jpg")
        XCTAssertEqual(books[1].coverURL?.absoluteString, "https://archive.org/services/img/notext_librivox")
    }

    func testErrorPayloadParsesAsEmpty() throws {
        let data = #"{"error":"No results found"}"#.data(using: .utf8)!
        XCTAssertEqual(try LibriVoxParser.parseBooks(data).count, 0)
    }

    func testStripHTML() {
        XCTAssertEqual(LibriVoxParser.stripHTML("<p>Hi <b>there</b></p>"), "Hi there")
    }
}
