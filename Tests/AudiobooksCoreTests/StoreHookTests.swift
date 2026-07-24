import XCTest
@testable import AudiobooksCore

final class StoreHookTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "test.hooks.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testSaveFiresPositionHook() {
        let store = ProgressStore(defaults: freshDefaults())
        var saved: PlaybackProgress?
        store.onPositionSaved = { saved = $0 }
        let progress = PlaybackProgress(bookID: 1, bookTitle: "B", coverURL: nil,
                                        sectionIndex: 0, seconds: 5, updatedAt: Date())
        store.save(progress)
        XCTAssertEqual(saved, progress)
    }

    func testMarkAndToggleFireFinishedHooks() {
        let store = ProgressStore(defaults: freshDefaults())
        var marked: [(Int, Int)] = []
        var unmarked: [(Int, Int)] = []
        store.onFinishedMarked = { marked.append(($0, $1)) }
        store.onFinishedUnmarked = { unmarked.append(($0, $1)) }

        store.markFinished(bookID: 7, sectionIndex: 2)
        store.toggleFinished(bookID: 7, sectionIndex: 2) // now unmarks
        store.toggleFinished(bookID: 7, sectionIndex: 2) // marks again

        XCTAssertEqual(marked.map { $0.0 }, [7, 7])
        XCTAssertEqual(marked.map { $0.1 }, [2, 2])
        XCTAssertEqual(unmarked.map { $0.1 }, [2])
    }

    func testApplyRemoteDoesNotFireHooksButPersists() {
        let defaults = freshDefaults()
        let store = ProgressStore(defaults: defaults)
        var hookFired = false
        store.onPositionSaved = { _ in hookFired = true }
        store.onFinishedMarked = { _, _ in hookFired = true }

        let progress = PlaybackProgress(bookID: 9, bookTitle: "R", coverURL: nil,
                                        sectionIndex: 1, seconds: 30, updatedAt: Date())
        store.applyRemote(items: [progress], finished: [9: [1]], hidden: [])

        XCTAssertFalse(hookFired)
        XCTAssertEqual(store.progress(for: 9)?.seconds, 30)
        XCTAssertTrue(store.isFinished(bookID: 9, sectionIndex: 1))

        let reloaded = ProgressStore(defaults: defaults)
        XCTAssertEqual(reloaded.progress(for: 9)?.seconds, 30)
    }

    func testToggleHiddenFiresHooksAndPersists() {
        let suite = "test.hidden.\(UUID().uuidString)"
        let store = ProgressStore(defaults: UserDefaults(suiteName: suite)!)
        var marked: [Int] = []
        var unmarked: [Int] = []
        store.onHiddenMarked = { marked.append($0) }
        store.onHiddenUnmarked = { unmarked.append($0) }

        XCTAssertFalse(store.isHidden(bookID: 52))
        store.toggleHidden(bookID: 52)
        XCTAssertTrue(store.isHidden(bookID: 52))
        store.toggleHidden(bookID: 52)
        XCTAssertFalse(store.isHidden(bookID: 52))
        XCTAssertEqual(marked, [52])
        XCTAssertEqual(unmarked, [52])

        store.toggleHidden(bookID: 7)
        let reloaded = ProgressStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(reloaded.isHidden(bookID: 7))
    }

    func testApplyRemoteHiddenFiresNoHooks() {
        let store = ProgressStore(defaults: freshDefaults())
        var fired = false
        store.onHiddenMarked = { _ in fired = true }
        store.onHiddenUnmarked = { _ in fired = true }

        store.applyRemote(items: [], finished: [:], hidden: [52])

        XCTAssertFalse(fired)
        XCTAssertTrue(store.isHidden(bookID: 52))
    }

    func testPreambleStoreHookAndApplyRemote() {
        let suite = "test.preamble.\(UUID().uuidString)"
        let store = PreambleOffsetStore(defaults: UserDefaults(suiteName: suite)!)
        var savedIDs: [String] = []
        store.onSaved = { id, _ in savedIDs.append(id) }

        store.save(offset: 12.5, sectionID: "52.3")
        XCTAssertEqual(savedIDs, ["52.3"])

        // applyRemote: no hook; existing local values win.
        store.applyRemote(offsets: ["52.3": 99.0, "52.4": 0])
        XCTAssertEqual(savedIDs, ["52.3"])
        XCTAssertEqual(store.offset(sectionID: "52.3"), 12.5)
        XCTAssertEqual(store.offset(sectionID: "52.4"), 0)
    }

    func testAllOffsetsExposesCachedOffsets() {
        let suite = "test.alloffsets.\(UUID().uuidString)"
        let store = PreambleOffsetStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(store.allOffsets, [:])
        store.save(offset: 12.5, sectionID: "52.3")
        store.save(offset: 0, sectionID: "52.4")
        XCTAssertEqual(store.allOffsets, ["52.3": 12.5, "52.4": 0])
    }
}
