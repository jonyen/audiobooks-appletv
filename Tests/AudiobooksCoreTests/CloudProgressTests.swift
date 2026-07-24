import XCTest
@testable import AudiobooksCore

final class CloudProgressTests: XCTestCase {
    private func pos(_ updatedAt: Double, seconds: Double = 10) -> CloudPosition {
        CloudPosition(bookTitle: "Book", coverURL: nil, sectionIndex: 0,
                      seconds: seconds, updatedAt: updatedAt)
    }

    func testSectionKeyMatchesWeb() {
        XCTAssertEqual(CloudProgress.sectionKey(bookID: 52, sectionIndex: 3), "52#3")
    }

    func testIsFinishedMarkTombstoneSemantics() {
        var state = CloudProgress.empty
        state.finishedMarks["52#3"] = 100
        XCTAssertTrue(state.isFinished(bookID: 52, sectionIndex: 3))
        state.unfinishedMarks["52#3"] = 200
        XCTAssertFalse(state.isFinished(bookID: 52, sectionIndex: 3))
        state.finishedMarks["52#3"] = 300
        XCTAssertTrue(state.isFinished(bookID: 52, sectionIndex: 3))
    }

    func testMergeTakesPerKeyMaximumsAndNewestPositions() {
        var a = CloudProgress.empty
        a.positions["1"] = pos(100, seconds: 42)
        a.finishedMarks["52#3"] = 300
        a.unfinishedMarks["52#3"] = 200
        var b = CloudProgress.empty
        b.positions["1"] = pos(300, seconds: 99)
        b.finishedMarks["52#3"] = 100
        b.unfinishedMarks["52#3"] = 400
        let merged = CloudProgress.merge(a, b)
        XCTAssertEqual(merged.positions["1"]?.seconds, 99)
        XCTAssertEqual(merged.finishedMarks["52#3"], 300)
        XCTAssertEqual(merged.unfinishedMarks["52#3"], 400)
        XCTAssertFalse(merged.isFinished(bookID: 52, sectionIndex: 3))
    }

    func testPositionMergeIsCommutativeOnExactTie() {
        var a = CloudProgress.empty
        a.positions["1"] = pos(100, seconds: 42)
        var b = CloudProgress.empty
        b.positions["1"] = pos(100, seconds: 99)
        let ab = CloudProgress.merge(a, b).positions["1"]
        let ba = CloudProgress.merge(b, a).positions["1"]
        XCTAssertEqual(ab, ba)
        XCTAssertEqual(ab?.seconds, 99) // deterministic winner: greater seconds on tie
    }

    func testStaleUnmarkCannotResurrectNewerRemark() {
        var a = CloudProgress.empty
        a.finishedMarks["52#3"] = 300
        a.unfinishedMarks["52#3"] = 200
        var b = CloudProgress.empty
        b.finishedMarks["52#3"] = 100
        b.unfinishedMarks["52#3"] = 200
        XCTAssertTrue(CloudProgress.merge(a, b).isFinished(bookID: 52, sectionIndex: 3))
    }

    func testFromLocalAndBackRoundTrips() {
        let now = Date(timeIntervalSince1970: 2000)
        let items = [PlaybackProgress(bookID: 52, bookTitle: "Pride", coverURL: nil,
                                      sectionIndex: 3, seconds: 42,
                                      updatedAt: Date(timeIntervalSince1970: 1000))]
        let cloud = CloudProgress.fromLocal(items: items, finished: [52: [0, 3]], now: now)
        XCTAssertEqual(cloud.positions["52"]?.updatedAt, 1_000_000) // ms epoch
        XCTAssertEqual(cloud.finishedMarks["52#0"], 2_000_000)
        XCTAssertEqual(cloud.finishedMarks["52#3"], 2_000_000)

        XCTAssertEqual(cloud.localItems.map(\.bookID), [52])
        XCTAssertEqual(cloud.localItems[0].seconds, 42)
        XCTAssertEqual(cloud.localFinished, [52: [0, 3]])
    }

    func testLocalItemsSortNewestFirstAndCapAtTwenty() {
        var cloud = CloudProgress.empty
        for i in 1...25 {
            cloud.positions[String(i)] = pos(Double(i) * 10)
        }
        let items = cloud.localItems
        XCTAssertEqual(items.count, 20)
        XCTAssertEqual(items.first?.bookID, 25)
        XCTAssertEqual(items.last?.bookID, 6)
    }

    func testDictionaryRoundTrip() {
        var cloud = CloudProgress.empty
        cloud.positions["52"] = CloudPosition(bookTitle: "Pride", coverURL: "https://x/y.jpg",
                                              sectionIndex: 3, seconds: 42, updatedAt: 1000)
        cloud.finishedMarks["52#3"] = 100
        cloud.unfinishedMarks["52#4"] = 200
        let decoded = CloudProgress.fromDictionary(cloud.asDictionary)
        XCTAssertEqual(decoded, cloud)
    }

    func testFromDictionaryIgnoresMalformedEntries() {
        let decoded = CloudProgress.fromDictionary([
            "positions": ["52": ["bookTitle": "Pride"], "bad": "not-a-dict"],
            "finishedMarks": ["52#3": 100.0, "bad": "nope"],
        ])
        // A position without required numeric fields is dropped; bad marks too.
        XCTAssertTrue(decoded.positions.isEmpty)
        XCTAssertEqual(decoded.finishedMarks, ["52#3": 100.0])
    }
}
