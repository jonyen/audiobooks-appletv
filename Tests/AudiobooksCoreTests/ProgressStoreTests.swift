import XCTest
@testable import AudiobooksCore

final class ProgressStoreTests: XCTestCase {
    var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "ProgressStoreTests")!
        defaults.removePersistentDomain(forName: "ProgressStoreTests")
    }

    func makeProgress(bookID: Int, seconds: Double = 10, date: Date = .init(timeIntervalSince1970: 1000)) -> PlaybackProgress {
        PlaybackProgress(bookID: bookID, bookTitle: "Book \(bookID)", coverURL: nil,
                         sectionIndex: 0, seconds: seconds, updatedAt: date)
    }

    func testSaveAndReload() {
        let store = ProgressStore(defaults: defaults)
        store.save(makeProgress(bookID: 1, seconds: 42))
        let reloaded = ProgressStore(defaults: defaults)
        XCTAssertEqual(reloaded.progress(for: 1)?.seconds, 42)
    }

    func testUpsertReplacesAndMovesToFront() {
        let store = ProgressStore(defaults: defaults)
        store.save(makeProgress(bookID: 1))
        store.save(makeProgress(bookID: 2))
        store.save(makeProgress(bookID: 1, seconds: 99))
        XCTAssertEqual(store.items.map(\.bookID), [1, 2])
        XCTAssertEqual(store.items[0].seconds, 99)
    }

    func testCapAtTwenty() {
        let store = ProgressStore(defaults: defaults)
        for i in 1...25 { store.save(makeProgress(bookID: i)) }
        XCTAssertEqual(store.items.count, 20)
        XCTAssertEqual(store.items.first?.bookID, 25)
        XCTAssertNil(store.progress(for: 1))
    }

    func testRemove() {
        let store = ProgressStore(defaults: defaults)
        store.save(makeProgress(bookID: 7))
        store.remove(bookID: 7)
        XCTAssertNil(store.progress(for: 7))
    }
}
