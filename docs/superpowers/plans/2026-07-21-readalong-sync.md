# Read-Along Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port BibleTV's reader features into AudiobooksTV: narrated-paragraph highlighting with auto-scroll, auto-hiding playback controls, and gold finished-section markers.

**Architecture:** A new `ParagraphTimeline` in the SPM `AudiobooksCore` target estimates per-paragraph narration times proportional to character counts (port of BibleTV's `VerseTimeline` estimator). `PlayerView` renders paragraphs as separate focusable `Text` blocks, dims all but the narrated one, and follows it with `ScrollPosition`. `ProgressStore` gains persisted finished-section sets that `BookDetailView` renders in gold.

**Tech Stack:** Swift 5.9, SwiftUI (tvOS 18 `ScrollPosition`), SPM test target `AudiobooksCoreTests` (runs on macOS via `swift test`), XcodeBuildMCP for simulator builds.

> **Deviation:** The app targets tvOS 17, not 18, so the `ScrollPosition`/`scrollTo(y:)` API isn't available. The implementation instead uses `.scrollPosition(id:anchor: .top)` with `.scrollTargetLayout()` and no `PreferenceKey` frame tracking. See Task 3.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-21-readalong-sync-design.md`
- The Xcode project uses synchronized file groups — new files under `AudiobooksTV/` are picked up automatically; never edit `project.pbxproj`.
- `AudiobooksTV/Core/` files must not import SwiftUI/UIKit (they build on macOS for tests). Views live in `AudiobooksTV/Views/`.
- Gold color, verbatim from BibleTV: `Color(red: 0.87, green: 0.72, blue: 0.4)`.
- Run unit tests from the repo root: `swift test`.
- Simulator verification: XcodeBuildMCP `build_run_sim` with the session defaults already set (AudiobooksTV scheme, Apple TV simulator `F7AA06DF-EBBB-4089-B709-10EC992EDF7B`).
- Work on branch `port-bibletv-reader-features`.

---

### Task 1: ParagraphTimeline

**Files:**
- Create: `AudiobooksTV/Core/ParagraphTimeline.swift`
- Test: `Tests/AudiobooksCoreTests/ParagraphTimelineTests.swift`

**Interfaces:**
- Consumes: nothing (pure Foundation).
- Produces: `ParagraphTimeline.paragraphs(from: String) -> [String]`, `ParagraphTimeline(paragraphs: [String], duration: Double)?`, `paragraphIndex(at: Double) -> Int?`. Task 3 relies on these exact names.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ParagraphTimelineTests`
Expected: compile FAILURE — `cannot find 'ParagraphTimeline' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Estimated narration start times for each paragraph of a chapter.
///
/// LibriVox audio has no timing metadata, so times are estimated by
/// splitting the section's duration across paragraphs in proportion to
/// their character counts. Recordings open with a short spoken preamble,
/// so early paragraphs run a few seconds behind the estimate; paragraph
/// granularity absorbs the drift.
struct ParagraphTimeline {
    private struct Entry {
        let start: Double
        let end: Double
    }

    private let entries: [Entry]

    /// Splits a chapter body into paragraphs on blank lines (lines that are
    /// empty or whitespace-only), trimming each paragraph and dropping
    /// empties. Handles CRLF input.
    static func paragraphs(from body: String) -> [String] {
        body.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .split(whereSeparator: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    init?(paragraphs: [String], duration: Double) {
        guard duration.isFinite, duration > 0, !paragraphs.isEmpty else { return nil }
        let counts = paragraphs.map(\.count)
        let total = counts.reduce(0, +)
        guard total > 0 else { return nil }

        var start = 0.0
        var entries: [Entry] = []
        for count in counts {
            let length = duration * Double(count) / Double(total)
            entries.append(Entry(start: start, end: start + length))
            start += length
        }
        self.entries = entries
    }

    /// The paragraph being narrated at a playback position. Positions before
    /// zero clamp to the first paragraph; positions at or past the end clamp
    /// to the last.
    func paragraphIndex(at seconds: Double) -> Int? {
        guard let last = entries.last else { return nil }
        if seconds < 0 { return 0 }
        if seconds >= last.end { return entries.count - 1 }
        return entries.firstIndex { seconds >= $0.start && seconds < $0.end }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ParagraphTimelineTests`
Expected: all 6 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add AudiobooksTV/Core/ParagraphTimeline.swift Tests/AudiobooksCoreTests/ParagraphTimelineTests.swift
git commit -m "feat: add ParagraphTimeline with estimated per-paragraph narration times"
```

---

### Task 2: ProgressStore finished sections

**Files:**
- Modify: `AudiobooksTV/Core/ProgressStore.swift`
- Test: `Tests/AudiobooksCoreTests/ProgressStoreTests.swift` (append tests)

**Interfaces:**
- Consumes: existing `ProgressStore` (UserDefaults-backed, `init(defaults:)`).
- Produces: `finishedSections(bookID: Int) -> Set<Int>`, `isFinished(bookID: Int, sectionIndex: Int) -> Bool`, `markFinished(bookID: Int, sectionIndex: Int)`, `toggleFinished(bookID: Int, sectionIndex: Int)`. Tasks 3–5 rely on these exact names. The backing `finished` dictionary is `@Published` so SwiftUI views observing the store refresh.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/AudiobooksCoreTests/ProgressStoreTests.swift` (match the file's existing fixture style for constructing a test `UserDefaults`; if it uses a helper, reuse it):

```swift
    func testMarkAndReadFinishedSections() {
        let defaults = UserDefaults(suiteName: "test.finished.\(UUID().uuidString)")!
        let store = ProgressStore(defaults: defaults)

        XCTAssertEqual(store.finishedSections(bookID: 7), [])
        XCTAssertFalse(store.isFinished(bookID: 7, sectionIndex: 2))

        store.markFinished(bookID: 7, sectionIndex: 2)
        store.markFinished(bookID: 7, sectionIndex: 2)  // idempotent
        store.markFinished(bookID: 7, sectionIndex: 5)

        XCTAssertEqual(store.finishedSections(bookID: 7), [2, 5])
        XCTAssertTrue(store.isFinished(bookID: 7, sectionIndex: 2))
        XCTAssertEqual(store.finishedSections(bookID: 8), [])
    }

    func testToggleFinished() {
        let defaults = UserDefaults(suiteName: "test.toggle.\(UUID().uuidString)")!
        let store = ProgressStore(defaults: defaults)

        store.toggleFinished(bookID: 3, sectionIndex: 1)
        XCTAssertTrue(store.isFinished(bookID: 3, sectionIndex: 1))
        store.toggleFinished(bookID: 3, sectionIndex: 1)
        XCTAssertFalse(store.isFinished(bookID: 3, sectionIndex: 1))
    }

    func testFinishedSectionsPersistAcrossInstances() {
        let suite = "test.persist.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        ProgressStore(defaults: defaults).markFinished(bookID: 9, sectionIndex: 0)

        let reloaded = ProgressStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reloaded.finishedSections(bookID: 9), [0])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProgressStoreTests`
Expected: compile FAILURE — `value of type 'ProgressStore' has no member 'finishedSections'`.

- [ ] **Step 3: Implement**

In `AudiobooksTV/Core/ProgressStore.swift`, add below the existing `key`/`cap` constants:

```swift
    private static let finishedKey = "finishedSections.v1"
```

Add a published dictionary below `items`:

```swift
    /// Finished section indexes per book ID. Feeds gold section titles.
    @Published private(set) var finished: [Int: Set<Int>] = [:]
```

At the end of `init`, load it:

```swift
        if let data = defaults.data(forKey: Self.finishedKey),
           let decoded = try? JSONDecoder().decode([Int: Set<Int>].self, from: data) {
            finished = decoded
        }
```

Add the API below `remove(bookID:)`:

```swift
    func finishedSections(bookID: Int) -> Set<Int> {
        finished[bookID] ?? []
    }

    func isFinished(bookID: Int, sectionIndex: Int) -> Bool {
        finished[bookID]?.contains(sectionIndex) ?? false
    }

    func markFinished(bookID: Int, sectionIndex: Int) {
        finished[bookID, default: []].insert(sectionIndex)
        persistFinished()
    }

    func toggleFinished(bookID: Int, sectionIndex: Int) {
        if isFinished(bookID: bookID, sectionIndex: sectionIndex) {
            finished[bookID]?.remove(sectionIndex)
            if finished[bookID]?.isEmpty == true {
                finished.removeValue(forKey: bookID)
            }
        } else {
            finished[bookID, default: []].insert(sectionIndex)
        }
        persistFinished()
    }

    private func persistFinished() {
        if let data = try? JSONEncoder().encode(finished) {
            defaults.set(data, forKey: Self.finishedKey)
        }
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests PASS (new ones plus no regressions).

- [ ] **Step 5: Commit**

```bash
git add AudiobooksTV/Core/ProgressStore.swift Tests/AudiobooksCoreTests/ProgressStoreTests.swift
git commit -m "feat: persist finished sections per book in ProgressStore"
```

---

### Task 3: PlayerView read-along sync (paragraph highlight + auto-scroll)

> **Deviation:** The steps below describe the tvOS 18 `ScrollPosition`/`scrollTo(y:)` + `PreferenceKey` frame-tracking approach originally planned. Since the app targets tvOS 17, the actual implementation uses `.scrollPosition(id:anchor: .top)` on the paragraph `VStack` (with `.scrollTargetLayout()`) and drives it from `scrollPositionID`/`.id(index)` instead — no frame tracking.

**Files:**
- Modify: `AudiobooksTV/Views/PlayerView.swift`

**Interfaces:**
- Consumes: `ParagraphTimeline` (Task 1) — `paragraphs(from:)`, `init?(paragraphs:duration:)`, `paragraphIndex(at:)`; existing `AudioPlayerModel` (`isPlaying`, `currentTime`, `duration` are `@Published`); `BookTextModel.chapter(forSectionIndex:)`; `BookTextModel.$chapters` publisher.
- Produces: `@FocusState focusedParagraph: Int?`, `controlsRevealed` state, and the paragraph rendering path that Task 4's controls work builds on.

- [ ] **Step 1: Add sync state and helpers**

In `PlayerView`, add state below `lastSavedSeconds`:

```swift
    @State private var paragraphs: [String] = []
    @State private var timeline: ParagraphTimeline?
    @State private var currentParagraphIndex: Int?
    @FocusState private var focusedParagraph: Int?
    @State private var followSuspendedUntil = Date.distantPast
    @State private var suppressFocusSuspension = false
    @State private var controlsRevealed = false
    @State private var paragraphFrames: [Int: CGRect] = [:]
    @State private var scrollPosition = ScrollPosition()

    /// Top padding of the read-along content, also used to convert paragraph
    /// frames into scroll-content offsets.
    private static let contentTopInset: CGFloat = 48
```

Add helper methods (below `saveProgress`):

```swift
    /// Re-derives paragraphs when the section or the loaded text changes,
    /// resetting all sync state.
    private func updateParagraphs() {
        if let chapter = textModel.chapter(forSectionIndex: sectionIndex) {
            paragraphs = ParagraphTimeline.paragraphs(from: chapter.body)
        } else {
            paragraphs = []
        }
        paragraphFrames = [:]
        currentParagraphIndex = nil
        followSuspendedUntil = .distantPast
        rebuildTimeline()
    }

    private func rebuildTimeline() {
        timeline = ParagraphTimeline(paragraphs: paragraphs, duration: audio.duration)
        currentParagraphIndex = timeline?.paragraphIndex(at: audio.currentTime)
    }

    /// Scrolls the narrated paragraph to the top of the frame unless the
    /// user recently moved focus manually.
    private func scrollToNarratedParagraph() {
        guard audio.isPlaying,
              Date() >= followSuspendedUntil,
              let index = currentParagraphIndex,
              let frame = paragraphFrames[index] else { return }
        let y = max(0, Self.contentTopInset + frame.minY - 16)
        withAnimation(.easeInOut(duration: 0.6)) {
            scrollPosition.scrollTo(y: y)
        }
    }
```

At the bottom of the file (outside `PlayerView`), add:

```swift
/// Collects each paragraph's frame (in read-along content coordinates) so
/// the player can scroll the narrated paragraph to the top.
private struct ParagraphFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
```

- [ ] **Step 2: Render paragraphs with highlight and follow**

Add a paragraph view builder next to `chapterScroll`:

```swift
    private var paragraphScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    // While playback runs the chapter dims as a whole and only
                    // the narrated paragraph renders at full brightness.
                    let dimmed = audio.isPlaying && index != currentParagraphIndex
                    Text(paragraph)
                        .font(.system(size: 38, design: .serif))
                        .foregroundStyle(dimmed ? Color.secondary : Color.primary)
                        .focusable()
                        .focused($focusedParagraph, equals: index)
                        .id(index)
                        .background(GeometryReader { geo in
                            Color.clear.preference(
                                key: ParagraphFramesKey.self,
                                value: [index: geo.frame(in: .named("readAlongContent"))]
                            )
                        })
                }
            }
            .coordinateSpace(name: "readAlongContent")
            .onPreferenceChange(ParagraphFramesKey.self) { paragraphFrames = $0 }
            .frame(maxWidth: 1200, alignment: .leading)
            .padding(.horizontal, 64)
            .padding(.top, Self.contentTopInset)
            // Generous bottom inset so the last lines can scroll clear of the
            // fold instead of being cut off.
            .padding(.bottom, 160)
        }
        .scrollPosition($scrollPosition)
        .onChange(of: focusedParagraph) {
            // Focus settling back into the text re-collapses controls that
            // were revealed with an up-press.
            if focusedParagraph != nil {
                controlsRevealed = false
            }
            // A user-driven focus move between paragraphs is a manual scroll:
            // pause following. Exempt are programmatic moves (play-start
            // handoff) and focus dropping to nil, which auto-scroll causes by
            // pushing the focused paragraph off-screen.
            if suppressFocusSuspension {
                suppressFocusSuspension = false
            } else if audio.isPlaying, focusedParagraph != nil {
                followSuspendedUntil = Date().addingTimeInterval(10)
            }
        }
        .onChange(of: currentParagraphIndex) {
            scrollToNarratedParagraph()
        }
    }
```

In `textBody`, change the aligned-chapter branch to use it, keeping the fallback paths untouched:

```swift
        } else if textModel.chapter(forSectionIndex: sectionIndex) != nil {
            paragraphScroll
        } else if case .loaded = textModel.state {
```

- [ ] **Step 3: Wire state updates into the body**

On the outer `VStack`'s modifier chain, extend `.task(id: sectionIndex)` and add subscriptions after it:

```swift
        .task(id: sectionIndex) {
            updateParagraphs()
            await startAudio()
        }
        .onReceive(textModel.$chapters) { _ in
            updateParagraphs()
        }
        .onChange(of: audio.duration) {
            rebuildTimeline()
        }
```

Extend the existing `.onChange(of: audio.currentTime)` handler's body with a first line:

```swift
            currentParagraphIndex = timeline?.paragraphIndex(at: newTime)
```

In `startAudio()`, after the `saveProgress(seconds: audio.currentTime)` line, hand focus to the text so highlighting starts from a clean focus state:

```swift
            if !paragraphs.isEmpty {
                suppressFocusSuspension = true
                focusedParagraph = 0
            }
```

- [ ] **Step 4: Build for the simulator to verify**

Run XcodeBuildMCP `build_sim` (defaults already set).
Expected: BUILD SUCCEEDED, no warnings about the new code.

- [ ] **Step 5: Commit**

```bash
git add AudiobooksTV/Views/PlayerView.swift
git commit -m "feat: highlight and auto-scroll the narrated paragraph in PlayerView"
```

---

### Task 4: Auto-hiding controls and finished-section marking

**Files:**
- Modify: `AudiobooksTV/Views/PlayerView.swift`

**Interfaces:**
- Consumes: Task 3's `controlsRevealed` / `focusedParagraph` state; Task 2's `ProgressStore.markFinished` / `toggleFinished` / `isFinished`.
- Produces: final PlayerView behavior; nothing downstream.

- [ ] **Step 1: Collapse controls during playback**

Add to `PlayerView`, below the state properties:

```swift
    @ObservedObject private var progressStore = ProgressStore.shared

    /// Controls stay visible while paused; during playback they collapse
    /// away entirely and only an explicit up-press at the top of the text
    /// reveals them. Loss of focus alone must NOT reveal them — auto-scroll
    /// can push the focused paragraph off-screen, which resets focus to nil
    /// without any user intent.
    private var controlsVisible: Bool {
        !audio.isPlaying || controlsRevealed
    }
```

Wrap the control bar and progress bar in the body:

```swift
            if controlsVisible {
                controlBar
                    .padding(.horizontal, 64)
                    .padding(.vertical, 24)

                progressBar
                    .padding(.horizontal, 64)
                    .padding(.bottom, 16)
            }
```

On the outer `VStack` modifier chain add (before `.navigationTitle`):

```swift
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        .onPlayPauseCommand {
            audio.togglePlayPause()
            if !audio.isPlaying {
                saveProgress(seconds: audio.currentTime)
            }
        }
        .onMoveCommand { direction in
            // Fires only when the focus engine has no target in that
            // direction — i.e. pressing up at the top of the text while the
            // controls are collapsed. Reveal them.
            if direction == .up {
                controlsRevealed = true
            }
        }
```

- [ ] **Step 2: Mark sections finished**

In `sectionFinished()`, record completion before the auto-advance guard:

```swift
    private func sectionFinished() {
        ProgressStore.shared.markFinished(bookID: book.id, sectionIndex: sectionIndex)
        guard autoAdvance, sectionIndex < book.sections.count - 1 else { return }
        sectionIndex += 1
    }
```

In `controlBar`, add a manual toggle after the auto-advance button:

```swift
            Button {
                ProgressStore.shared.toggleFinished(bookID: book.id, sectionIndex: sectionIndex)
            } label: {
                let isFinished = progressStore.isFinished(bookID: book.id, sectionIndex: sectionIndex)
                Label(
                    isFinished ? "Mark as Unfinished" : "Mark as Finished",
                    systemImage: isFinished ? "checkmark.circle.fill" : "checkmark.circle"
                )
                .labelStyle(.iconOnly)
            }
            .foregroundStyle(
                progressStore.isFinished(bookID: book.id, sectionIndex: sectionIndex)
                    ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
            )
```

- [ ] **Step 3: Build for the simulator to verify**

Run XcodeBuildMCP `build_sim`.
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add AudiobooksTV/Views/PlayerView.swift
git commit -m "feat: auto-hide player controls during playback; mark finished sections"
```

---

### Task 5: Gold finished-section titles in BookDetailView

**Files:**
- Modify: `AudiobooksTV/Views/BookDetailView.swift`

**Interfaces:**
- Consumes: Task 2's `ProgressStore.isFinished(bookID:sectionIndex:)` and `@Published finished` (drives view refresh).
- Produces: final UI; nothing downstream.

- [ ] **Step 1: Render finished titles in gold**

Add to `BookDetailView` below `playTarget`:

```swift
    @ObservedObject private var progressStore = ProgressStore.shared

    /// Finished sections render in a warm gold instead of the default label
    /// color, matching BibleTV's read-chapter treatment.
    private static let finishedColor = Color(red: 0.87, green: 0.72, blue: 0.4)
```

In the chapters `ForEach`, color the title:

```swift
                            Text(section.title)
                                .foregroundStyle(
                                    progressStore.isFinished(bookID: book.id, sectionIndex: index)
                                        ? Self.finishedColor : Color.primary
                                )
```

- [ ] **Step 2: Build for the simulator to verify**

Run XcodeBuildMCP `build_sim`.
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add AudiobooksTV/Views/BookDetailView.swift
git commit -m "feat: gold titles for finished sections in book detail"
```

---

### Task 6: Full verification and deploy

**Files:** none (verification only).

- [ ] **Step 1: Run the full unit test suite**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 2: Build, install, and launch on the Apple TV simulator**

Run XcodeBuildMCP `build_run_sim`.
Expected: BUILD SUCCEEDED, app launches.

- [ ] **Step 3: Drive the app and verify each feature**

Using XcodeBuildMCP `snapshot_ui` + `tap` + `screenshot`:
1. Open a book with read-along text (e.g. "Bleak House"), press Play.
2. Screenshot during playback: controls collapsed, one paragraph at full
   brightness with the rest dimmed.
3. Wait ~30s, screenshot again: highlighted paragraph advanced/followed.
4. Press up at the top of the text: controls reveal; toggle the checkmark.
5. Back out to book detail: that section's title renders gold.

- [ ] **Step 4: Report results to the user with screenshots**
