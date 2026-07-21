# Preamble Skip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically skip the spoken LibriVox credits at the start of each section, and feed the detected offset into the read-along timeline as `leadIn`.

**Architecture:** A pure `PreambleDetector` finds the longest qualifying silence in RMS loudness windows; `AudioAnalyzer` (AVAssetReader) produces those windows from the first 60s of the cached file; `PreambleOffsetStore` caches results per section; `PlayerView` resolves the offset on fresh section starts, seeks past it, and passes it to `ParagraphTimeline`, which gains a `leadIn` parameter.

**Tech Stack:** Swift 5.9, AVFoundation (app target only), SPM test target `AudiobooksCoreTests` (`swift test` on macOS).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-21-preamble-skip-design.md`
- New files under `AudiobooksTV/` are picked up automatically; never edit `project.pbxproj`.
- `AudiobooksTV/Core/` files: Foundation only — no SwiftUI/UIKit/AVFoundation (they build on macOS for tests). AVFoundation code goes in `AudiobooksTV/Services/`.
- Detection constants, verbatim from the spec: `silenceFloorFraction = 0.2` (of the median non-zero RMS), `minSilence = 0.8` s, `minEnd = 8.0` s, `maxEnd = 60.0` s, analysis window 0.05 s, analysis limit 60 s.
- `leadIn` clamps to `[0, duration * 0.5]`.
- Offset cache key: `"\(book.id).\(sectionIndex)"`; a stored `0` means "analyzed, nothing to skip".
- Run unit tests from the repo root: `swift test`.
- Simulator build verification: `xcodebuild -project AudiobooksTV.xcodeproj -scheme AudiobooksTV -destination 'platform=tvOS Simulator,id=F7AA06DF-EBBB-4089-B709-10EC992EDF7B' build`
- Work on branch `preamble-skip`.

---

### Task 1: PreambleDetector

**Files:**
- Create: `AudiobooksTV/Core/PreambleDetector.swift`
- Test: `Tests/AudiobooksCoreTests/PreambleDetectorTests.swift`

**Interfaces:**
- Consumes: nothing (pure Foundation).
- Produces: `PreambleDetector.preambleEnd(windowRMS: [Float], windowDuration: Double) -> Double?`. Task 4 calls this exact name.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AudiobooksCore

final class PreambleDetectorTests: XCTestCase {

    /// Builds an RMS array from (level, seconds) segments at 0.1s windows.
    private func windows(_ segments: [(level: Float, seconds: Double)]) -> [Float] {
        segments.flatMap { Array(repeating: $0.level, count: Int($0.seconds * 10)) }
    }

    func testPicksLongestQualifyingSilence() {
        // 10s speech, 1s pause, 9s speech, 2s pause (ends at 22s), 10s speech.
        let rms = windows([(1.0, 10), (0.0, 1), (1.0, 9), (0.0, 2), (1.0, 10)])
        XCTAssertEqual(PreambleDetector.preambleEnd(windowRMS: rms, windowDuration: 0.1)!,
                       22.0, accuracy: 0.11)
    }

    func testIgnoresSilenceEndingBeforeMinEnd() {
        // Only pause ends at 4s — inside the credits, not after them.
        let rms = windows([(1.0, 2), (0.0, 2), (1.0, 26)])
        XCTAssertNil(PreambleDetector.preambleEnd(windowRMS: rms, windowDuration: 0.1))
    }

    func testIgnoresShortSilences() {
        // Pauses of 0.5s never qualify (minSilence 0.8).
        let rms = windows([(1.0, 10), (0.0, 0.5), (1.0, 10), (0.0, 0.5), (1.0, 10)])
        XCTAssertNil(PreambleDetector.preambleEnd(windowRMS: rms, windowDuration: 0.1))
    }

    func testNilForNoSilenceAllZeroOrEmpty() {
        XCTAssertNil(PreambleDetector.preambleEnd(windowRMS: windows([(1.0, 30)]), windowDuration: 0.1))
        XCTAssertNil(PreambleDetector.preambleEnd(windowRMS: windows([(0.0, 30)]), windowDuration: 0.1))
        XCTAssertNil(PreambleDetector.preambleEnd(windowRMS: [], windowDuration: 0.1))
        XCTAssertNil(PreambleDetector.preambleEnd(windowRMS: [1, 0, 1], windowDuration: 0))
    }

    func testSilenceIsRelativeToMedianLevel() {
        // Quiet-but-voiced windows (0.5 of median 1.0) are NOT silence;
        // windows at 0.1 of median are.
        let rms = windows([(1.0, 10), (0.5, 2), (1.0, 5), (0.1, 1), (1.0, 12)])
        XCTAssertEqual(PreambleDetector.preambleEnd(windowRMS: rms, windowDuration: 0.1)!,
                       18.0, accuracy: 0.11)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreambleDetectorTests`
Expected: compile FAILURE — `cannot find 'PreambleDetector' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Finds the end of the spoken LibriVox credits at the start of a section.
///
/// Operates on RMS loudness windows of the clip's opening seconds. The
/// preamble end is the end of the longest silence whose end falls within
/// [minEnd, maxEnd] — narrators leave their largest pause between the
/// credits and the chapter text.
enum PreambleDetector {
    static let silenceFloorFraction: Float = 0.2
    static let minSilence = 0.8
    static let minEnd = 8.0
    static let maxEnd = 60.0

    static func preambleEnd(windowRMS: [Float], windowDuration: Double) -> Double? {
        guard windowDuration > 0, !windowRMS.isEmpty else { return nil }
        let nonZero = windowRMS.filter { $0 > 0 }.sorted()
        guard !nonZero.isEmpty else { return nil }
        let floor = nonZero[nonZero.count / 2] * silenceFloorFraction

        // Collect maximal runs of silent windows as (startIndex, count).
        var runs: [(start: Int, count: Int)] = []
        var runStart: Int?
        for (index, rms) in windowRMS.enumerated() {
            if rms < floor {
                if runStart == nil { runStart = index }
            } else if let start = runStart {
                runs.append((start, index - start))
                runStart = nil
            }
        }
        if let start = runStart {
            runs.append((start, windowRMS.count - start))
        }

        let qualifying = runs.filter { run in
            let length = Double(run.count) * windowDuration
            let end = Double(run.start + run.count) * windowDuration
            return length >= minSilence && end >= minEnd && end <= maxEnd
        }
        guard let longest = qualifying.max(by: { $0.count < $1.count }) else { return nil }
        return Double(longest.start + longest.count) * windowDuration
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PreambleDetectorTests`
Expected: all 5 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add AudiobooksTV/Core/PreambleDetector.swift Tests/AudiobooksCoreTests/PreambleDetectorTests.swift
git commit -m "feat: add PreambleDetector finding the longest credits-ending silence"
```

---

### Task 2: ParagraphTimeline leadIn

**Files:**
- Modify: `AudiobooksTV/Core/ParagraphTimeline.swift`
- Test: `Tests/AudiobooksCoreTests/ParagraphTimelineTests.swift` (append tests)

**Interfaces:**
- Consumes: existing `ParagraphTimeline`.
- Produces: `init?(paragraphs: [String], duration: Double, leadIn: Double = 0)` — the default preserves every existing call site and test unchanged. Task 4 passes `leadIn:` explicitly.

- [ ] **Step 1: Append the failing tests**

Append inside `ParagraphTimelineTests`:

```swift
    func testLeadInShiftsAllStarts() {
        // leadIn 10 over 40s, paragraphs 10 and 30 chars:
        // paragraph 0 spans 10..17.5, paragraph 1 spans 17.5..40.
        let timeline = ParagraphTimeline(
            paragraphs: [String(repeating: "a", count: 10),
                         String(repeating: "b", count: 30)],
            duration: 40, leadIn: 10
        )
        XCTAssertEqual(timeline?.paragraphIndex(at: 12), 0)
        XCTAssertEqual(timeline?.paragraphIndex(at: 18), 1)
    }

    func testPositionsBeforeLeadInClampToFirstParagraph() {
        let timeline = ParagraphTimeline(paragraphs: ["aaa", "bbb"], duration: 40, leadIn: 10)
        XCTAssertEqual(timeline?.paragraphIndex(at: 0), 0)
        XCTAssertEqual(timeline?.paragraphIndex(at: 9.9), 0)
    }

    func testLeadInClampsToHalfDurationAndNegativeToZero() {
        // leadIn 30 of 40s clamps to 20: position 19 is still before paragraph 0.
        let clamped = ParagraphTimeline(paragraphs: ["aaa", "bbb"], duration: 40, leadIn: 30)
        XCTAssertEqual(clamped?.paragraphIndex(at: 19), 0)
        XCTAssertEqual(clamped?.paragraphIndex(at: 31), 1)
        // Negative leadIn behaves as 0.
        let negative = ParagraphTimeline(paragraphs: ["aaa", "bbb"], duration: 10, leadIn: -5)
        XCTAssertEqual(negative?.paragraphIndex(at: 6), 1)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ParagraphTimelineTests`
Expected: compile FAILURE — `extra argument 'leadIn' in call`.

- [ ] **Step 3: Implement**

Replace the initializer and the two `paragraphIndex` clamp lines:

```swift
    init?(paragraphs: [String], duration: Double, leadIn: Double = 0) {
        guard duration.isFinite, duration > 0, !paragraphs.isEmpty else { return nil }
        let counts = paragraphs.map(\.count)
        let total = counts.reduce(0, +)
        guard total > 0 else { return nil }

        // A preamble is never half the section; clamping keeps a bogus
        // cached offset from wrecking the whole timeline.
        let clampedLeadIn = min(max(0, leadIn), duration * 0.5)
        let spoken = duration - clampedLeadIn
        var start = clampedLeadIn
        var entries: [Entry] = []
        for count in counts {
            let length = spoken * Double(count) / Double(total)
            entries.append(Entry(start: start, end: start + length))
            start += length
        }
        self.entries = entries
    }
```

In `paragraphIndex(at:)`, replace `if seconds < 0 { return 0 }` with:

```swift
        if let first = entries.first, seconds < first.start { return 0 }
```

- [ ] **Step 4: Run the full suite to verify old and new tests pass**

Run: `swift test`
Expected: all tests PASS, including the pre-existing ParagraphTimeline tests unchanged.

- [ ] **Step 5: Commit**

```bash
git add AudiobooksTV/Core/ParagraphTimeline.swift Tests/AudiobooksCoreTests/ParagraphTimelineTests.swift
git commit -m "feat: ParagraphTimeline leadIn shifts estimates past the preamble"
```

---

### Task 3: PreambleOffsetStore

**Files:**
- Create: `AudiobooksTV/Core/PreambleOffsetStore.swift`
- Test: `Tests/AudiobooksCoreTests/PreambleOffsetStoreTests.swift`

**Interfaces:**
- Consumes: nothing (Foundation + UserDefaults).
- Produces: `PreambleOffsetStore.shared`, `func offset(sectionID: String) -> Double?` (nil = never analyzed; 0 = analyzed, no skip), `func save(offset: Double, sectionID: String)`. Task 4 calls these exact names.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PreambleOffsetStoreTests`
Expected: compile FAILURE — `cannot find 'PreambleOffsetStore' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Caches detected preamble offsets per audio section so silence analysis
/// runs at most once per section. A stored 0 means "analyzed, nothing to
/// skip"; a missing key means "never analyzed".
final class PreambleOffsetStore {
    static let shared = PreambleOffsetStore()
    private static let key = "preambleOffsets.v1"

    private var offsets: [String: Double]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        offsets = (defaults.dictionary(forKey: Self.key) as? [String: Double]) ?? [:]
    }

    func offset(sectionID: String) -> Double? {
        offsets[sectionID]
    }

    func save(offset: Double, sectionID: String) {
        offsets[sectionID] = offset
        defaults.set(offsets, forKey: Self.key)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add AudiobooksTV/Core/PreambleOffsetStore.swift Tests/AudiobooksCoreTests/PreambleOffsetStoreTests.swift
git commit -m "feat: cache detected preamble offsets per section"
```

---

### Task 4: AudioAnalyzer and PlayerView wiring

**Files:**
- Create: `AudiobooksTV/Services/AudioAnalyzer.swift`
- Modify: `AudiobooksTV/Views/PlayerView.swift`

**Interfaces:**
- Consumes: `PreambleDetector.preambleEnd(windowRMS:windowDuration:)` (Task 1), `ParagraphTimeline(paragraphs:duration:leadIn:)` (Task 2), `PreambleOffsetStore.shared.offset(sectionID:)` / `.save(offset:sectionID:)` (Task 3), existing `AudioPlayerModel.seek(to:)` and `LibriVoxClient.shared.audioFile(for:)`.
- Produces: final behavior; nothing downstream.

- [ ] **Step 1: Write AudioAnalyzer**

```swift
import AVFoundation

/// Decodes the opening seconds of a local audio file into RMS loudness
/// windows for preamble detection.
enum AudioAnalyzer {
    static func rmsWindows(
        fileURL: URL, windowDuration: Double, limit: Double
    ) async throws -> [Float] {
        let asset = AVURLAsset(url: fileURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: limit, preferredTimescale: 600)
        )
        let sampleRate = 16_000.0
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ])
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? CocoaError(.fileReadUnknown)
        }

        let windowSamples = max(1, Int(sampleRate * windowDuration))
        var windows: [Float] = []
        var sumSquares = 0.0
        var samplesInWindow = 0

        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var totalLength = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(
                block, atOffset: 0, lengthAtOffsetOut: nil,
                totalLengthOut: &totalLength, dataPointerOut: &pointer
            ) == kCMBlockBufferNoErr, let pointer else { continue }

            let sampleCount = totalLength / MemoryLayout<Float>.size
            pointer.withMemoryRebound(to: Float.self, capacity: sampleCount) { samples in
                for i in 0..<sampleCount {
                    let sample = Double(samples[i])
                    sumSquares += sample * sample
                    samplesInWindow += 1
                    if samplesInWindow == windowSamples {
                        windows.append(Float((sumSquares / Double(samplesInWindow)).squareRoot()))
                        sumSquares = 0
                        samplesInWindow = 0
                    }
                }
            }
        }
        if samplesInWindow > 0 {
            windows.append(Float((sumSquares / Double(samplesInWindow)).squareRoot()))
        }
        return windows
    }
}
```

- [ ] **Step 2: Wire the skip into PlayerView**

Read `AudiobooksTV/Views/PlayerView.swift` fully first. Then:

Add state below the existing sync state:

```swift
    @State private var preambleOffset: Double = 0
```

In `.task(id: sectionIndex)`, reset it before the existing calls:

```swift
        .task(id: sectionIndex) {
            preambleOffset = 0
            updateParagraphs()
            await startAudio()
        }
```

In `rebuildTimeline()`, pass the offset:

```swift
        timeline = ParagraphTimeline(paragraphs: paragraphs, duration: audio.duration, leadIn: preambleOffset)
```

In `startAudio()`, capture fresh-start at entry (first line of the method):

```swift
        let freshStart = pendingSeekSeconds == 0
```

and after the existing `saveProgress(seconds: audio.currentTime)` call in the success path, launch resolution:

```swift
            if freshStart {
                let analyzedSection = sectionIndex
                Task { await resolvePreambleSkip(fileURL: fileURL, analyzedSection: analyzedSection) }
            }
```

Add the resolver below `saveProgress`:

```swift
    /// Looks up or computes the section's preamble offset, then jumps past
    /// the spoken credits if playback is still inside them. Bails silently
    /// if the section changed while analyzing.
    private func resolvePreambleSkip(fileURL: URL, analyzedSection: Int) async {
        let sectionID = "\(book.id).\(analyzedSection)"
        var offset = PreambleOffsetStore.shared.offset(sectionID: sectionID)
        if offset == nil {
            let windows = (try? await AudioAnalyzer.rmsWindows(
                fileURL: fileURL, windowDuration: 0.05, limit: 60
            )) ?? []
            guard sectionIndex == analyzedSection else { return }
            let detected = PreambleDetector.preambleEnd(windowRMS: windows, windowDuration: 0.05) ?? 0
            PreambleOffsetStore.shared.save(offset: detected, sectionID: sectionID)
            offset = detected
        }
        guard let offset, offset > 0, sectionIndex == analyzedSection else { return }
        preambleOffset = offset
        rebuildTimeline()
        if audio.currentTime < offset {
            audio.seek(to: offset)
        }
    }
```

- [ ] **Step 3: Build for the simulator and run core tests**

Run the Global Constraints `xcodebuild` command. Expected: BUILD SUCCEEDED, no new warnings.
Run: `swift test`. Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add AudiobooksTV/Services/AudioAnalyzer.swift AudiobooksTV/Views/PlayerView.swift
git commit -m "feat: auto-skip LibriVox spoken credits on fresh section starts"
```

---

### Task 5: Full verification and deploy

**Files:** none (verification only).

- [ ] **Step 1:** `swift test` — all tests pass.
- [ ] **Step 2:** XcodeBuildMCP `build_run_sim` — app launches on the Apple TV simulator.
- [ ] **Step 3:** Start a book section from the beginning; confirm via the runtime log or the progress bar that playback jumps forward within the first seconds, and that the read-along highlight starts on the first paragraph at the jump rather than partway in.
- [ ] **Step 4:** Report results to the user.
