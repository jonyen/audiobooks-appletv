import XCTest
@testable import AudiobooksCore

final class PreambleOffsetStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "PreambleOffsetStoreTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testMissingSectionReturnsNil() {
        XCTAssertNil(PreambleOffsetStore(defaults: defaults).offset(sectionID: "1.0"))
    }

    func testSaveAndReadBackIncludingZeroSentinel() {
        let store = PreambleOffsetStore(defaults: defaults)
        store.save(offset: 14.5, sectionID: "1.0")
        store.save(offset: 0, sectionID: "1.1")
        XCTAssertEqual(store.offset(sectionID: "1.0"), 14.5)
        XCTAssertEqual(store.offset(sectionID: "1.1"), 0)
        XCTAssertNil(store.offset(sectionID: "1.2"))
    }

    func testPersistsAcrossInstances() {
        PreambleOffsetStore(defaults: defaults).save(offset: 9.25, sectionID: "7.3")
        XCTAssertEqual(PreambleOffsetStore(defaults: defaults).offset(sectionID: "7.3"), 9.25)
    }
}
