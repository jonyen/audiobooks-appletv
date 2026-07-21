# AudiobooksTV Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform the BibleTV tvOS app into AudiobooksTV — a read-along audiobook player streaming LibriVox audio with matching Project Gutenberg text on screen.

**Architecture:** Same three-layer shape as BibleTV (Models / Services / Views) inside one Xcode tvOS target. Pure-logic code (parsing, chapter splitting, section↔chapter alignment, progress persistence) lives in `AudiobooksTV/Core/`, which is ALSO exposed as an SPM target so `swift test` runs on macOS with no simulator. Network clients (`LibriVoxClient`, `GutenbergClient`) and AV code stay app-only under `Services/`. Views are SwiftUI.

**Tech Stack:** Swift 5.9+, SwiftUI, AVFoundation, tvOS 17.0, Xcode 16, SPM test harness (XCTest). Zero external dependencies. Zero API keys.

## Global Constraints

- tvOS deployment target: **17.0** (already set in pbxproj; do not change)
- Bundle id after rename: `com.jonyen.AudiobooksTV`
- No third-party dependencies; Foundation/SwiftUI/AVFoundation only
- No API keys anywhere; `Secrets.swift` must be gone by end of Task 12
- Regex literals in `Core/` files MUST use extended delimiters `#/…/#` (bare `/…/` breaks SPM builds without an upcoming-feature flag)
- All new Swift files in `AudiobooksTV/` are auto-included in the app target (fileSystemSynchronized root group) — never edit `project.pbxproj` to add files
- Build check command (used repeatedly):
  `xcodebuild -project AudiobooksTV.xcodeproj -scheme AudiobooksTV -destination 'platform=tvOS Simulator,name=Apple TV' build`
- Test command: `swift test` (from repo root)
- Commit messages: conventional (`feat:`, `refactor:`, `test:`, `docs:`), each ending with the two Claude trailer lines used in this repo's history

---

### Task 1: Rename project BibleTV → AudiobooksTV

**Files:**
- Rename: `BibleTV/` → `AudiobooksTV/`, `BibleTV.xcodeproj/` → `AudiobooksTV.xcodeproj/`
- Rename: `AudiobooksTV/BibleTVApp.swift` → `AudiobooksTV/AudiobooksTVApp.swift`
- Modify: `AudiobooksTV.xcodeproj/project.pbxproj` (global string replace)

**Interfaces:**
- Consumes: nothing
- Produces: Xcode project `AudiobooksTV.xcodeproj`, scheme `AudiobooksTV`, app entry struct `AudiobooksTVApp`. Bible-era code still present and building.

- [ ] **Step 1: Rename directories and app file**

```bash
cd /Users/jyen/Projects/audiobooks-appletv
git mv BibleTV AudiobooksTV
git mv BibleTV.xcodeproj AudiobooksTV.xcodeproj
git mv AudiobooksTV/BibleTVApp.swift AudiobooksTV/AudiobooksTVApp.swift
sed -i '' 's/BibleTV/AudiobooksTV/g' AudiobooksTV.xcodeproj/project.pbxproj
```

This also flips `PRODUCT_BUNDLE_IDENTIFIER` to `com.jonyen.AudiobooksTV` (it contains the string `BibleTV`).

- [ ] **Step 2: Update the app entry struct**

Replace the full contents of `AudiobooksTV/AudiobooksTVApp.swift` with:

```swift
import SwiftUI

@main
struct AudiobooksTVApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if Secrets.esvAPIKey.isEmpty {
                    SetupView()
                } else {
                    BookListView()
                }
            }
        }
    }
}
```

(Bible views are deleted in Task 12; keep them compiling until then.)

- [ ] **Step 3: Build to verify rename**

Run: `xcodebuild -project AudiobooksTV.xcodeproj -scheme AudiobooksTV -destination 'platform=tvOS Simulator,name=Apple TV' build 2>&1 | tail -3`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: rename BibleTV project to AudiobooksTV"
```

---

### Task 2: SPM test harness + RomanNumerals

**Files:**
- Create: `Package.swift`
- Create: `AudiobooksTV/Core/RomanNumerals.swift`
- Create: `Tests/AudiobooksCoreTests/RomanNumeralsTests.swift`
- Modify: `.gitignore` (append `.build/`)

**Interfaces:**
- Consumes: nothing
- Produces: `RomanNumerals.parse(_ s: String) -> Int?` (nil for invalid; case-insensitive). SPM target `AudiobooksCore` covering `AudiobooksTV/Core`; tests use `@testable import AudiobooksCore`.

- [ ] **Step 1: Create the package manifest**

`Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudiobooksCore",
    platforms: [.macOS(.v13), .tvOS(.v17)],
    targets: [
        .target(name: "AudiobooksCore", path: "AudiobooksTV/Core"),
        .testTarget(
            name: "AudiobooksCoreTests",
            dependencies: ["AudiobooksCore"],
            path: "Tests/AudiobooksCoreTests"
        ),
    ]
)
```

Append `.build/` to `.gitignore`.

- [ ] **Step 2: Write the failing test**

`Tests/AudiobooksCoreTests/RomanNumeralsTests.swift`:

```swift
import XCTest
@testable import AudiobooksCore

final class RomanNumeralsTests: XCTestCase {
    func testParsesBasicNumerals() {
        XCTAssertEqual(RomanNumerals.parse("I"), 1)
        XCTAssertEqual(RomanNumerals.parse("IV"), 4)
        XCTAssertEqual(RomanNumerals.parse("IX"), 9)
        XCTAssertEqual(RomanNumerals.parse("XIX"), 19)
        XCTAssertEqual(RomanNumerals.parse("XLII"), 42)
        XCTAssertEqual(RomanNumerals.parse("MCMXCIV"), 1994)
    }

    func testCaseInsensitive() {
        XCTAssertEqual(RomanNumerals.parse("xii"), 12)
    }

    func testRejectsInvalid() {
        XCTAssertNil(RomanNumerals.parse(""))
        XCTAssertNil(RomanNumerals.parse("ABC"))
        XCTAssertNil(RomanNumerals.parse("IL"))
        XCTAssertNil(RomanNumerals.parse("chapter"))
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test 2>&1 | tail -5`
Expected: FAIL — `cannot find 'RomanNumerals' in scope` (compile error counts as the failing state)

- [ ] **Step 4: Write the implementation**

`AudiobooksTV/Core/RomanNumerals.swift`:

```swift
import Foundation

enum RomanNumerals {
    private static let values: [(Int, String)] = [
        (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
        (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
        (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
    ]

    /// Parses a Roman numeral (case-insensitive). Returns nil if the string
    /// contains non-numeral characters or is not consumable greedily.
    static func parse(_ s: String) -> Int? {
        let s = s.uppercased()
        guard !s.isEmpty, s.allSatisfy({ "MDCLXVI".contains($0) }) else { return nil }
        var total = 0
        var index = s.startIndex
        for (value, symbol) in values {
            while s[index...].hasPrefix(symbol) {
                total += value
                index = s.index(index, offsetBy: symbol.count)
                if index == s.endIndex { return total }
            }
        }
        return index == s.endIndex ? total : nil
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 6: Build the app target still passes, then commit**

Run the build check command; expected `BUILD SUCCEEDED`.

```bash
git add Package.swift .gitignore AudiobooksTV/Core Tests
git commit -m "feat: add SPM test harness and RomanNumerals parser"
```

---

### Task 3: GutenbergText — ebook ID extraction + boilerplate stripping

**Files:**
- Create: `AudiobooksTV/Core/GutenbergText.swift`
- Test: `Tests/AudiobooksCoreTests/GutenbergTextTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `GutenbergText.ebookID(fromTextSource url: String) -> Int?`
  - `GutenbergText.stripBoilerplate(_ raw: String) -> String`

- [ ] **Step 1: Write the failing tests**

`Tests/AudiobooksCoreTests/GutenbergTextTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test 2>&1 | tail -5`
Expected: FAIL — `cannot find 'GutenbergText' in scope`

- [ ] **Step 3: Write the implementation**

`AudiobooksTV/Core/GutenbergText.swift`:

```swift
import Foundation

enum GutenbergText {
    /// Extracts the Project Gutenberg ebook ID from a LibriVox `url_text_source`
    /// value. Returns nil when the source is not a gutenberg.org URL.
    static func ebookID(fromTextSource url: String) -> Int? {
        guard url.contains("gutenberg.org") else { return nil }
        let patterns = [
            #/\/etext\/(\d+)/#,
            #/\/ebooks\/(\d+)/#,
            #/\/files\/(\d+)/#,
            #/\/epub\/(\d+)/#,
        ]
        for pattern in patterns {
            if let match = url.firstMatch(of: pattern) {
                return Int(match.1)
            }
        }
        return nil
    }

    /// Removes the Project Gutenberg license header and footer, keeping only
    /// the book body. Texts without markers are returned trimmed but intact.
    static func stripBoilerplate(_ raw: String) -> String {
        var text = raw
        if let start = text.range(
            of: #"\*\*\* ?START OF TH(E|IS) PROJECT GUTENBERG EBOOK[^\n]*"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            text = String(text[start.upperBound...])
        }
        if let end = text.range(
            of: #"\*\*\* ?END OF TH(E|IS) PROJECT GUTENBERG EBOOK"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            text = String(text[..<end.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 5: Commit**

```bash
git add AudiobooksTV/Core/GutenbergText.swift Tests/AudiobooksCoreTests/GutenbergTextTests.swift
git commit -m "feat: add Gutenberg ID extraction and boilerplate stripping"
```

---

### Task 4: ChapterSplitter

**Files:**
- Create: `AudiobooksTV/Core/ChapterSplitter.swift`
- Test: `Tests/AudiobooksCoreTests/ChapterSplitterTests.swift`

**Interfaces:**
- Consumes: `RomanNumerals.parse`
- Produces:
  - `struct TextChapter: Equatable { let title: String; let body: String }`
  - `ChapterSplitter.split(_ text: String) -> [TextChapter]` — returns a single chapter titled `"Full Text"` when fewer than 2 headings found

- [ ] **Step 1: Write the failing tests**

`Tests/AudiobooksCoreTests/ChapterSplitterTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test 2>&1 | tail -5`
Expected: FAIL — `cannot find 'ChapterSplitter' in scope`

- [ ] **Step 3: Write the implementation**

`AudiobooksTV/Core/ChapterSplitter.swift`:

```swift
import Foundation

struct TextChapter: Equatable {
    let title: String
    let body: String
}

enum ChapterSplitter {
    /// Splits a Gutenberg plain text into chapters by heading lines.
    /// A heading is a short line, preceded by a blank line (or text start),
    /// matching a chapter-keyword pattern or a bare Roman/Arabic numeral.
    static func split(_ text: String) -> [TextChapter] {
        let lines = text.components(separatedBy: "\n")
        var headingIndices: [Int] = []

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.count <= 80 else { continue }
            let previousBlank = i == 0
                || lines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty
            guard previousBlank, isHeading(trimmed) else { continue }
            headingIndices.append(i)
        }

        guard headingIndices.count >= 2 else {
            return [TextChapter(title: "Full Text", body: text)]
        }

        var chapters: [TextChapter] = []
        for (n, start) in headingIndices.enumerated() {
            let end = n + 1 < headingIndices.count ? headingIndices[n + 1] : lines.count
            let title = lines[start].trimmingCharacters(in: .whitespaces)
            let body = lines[(start + 1)..<end]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            chapters.append(TextChapter(title: title, body: body))
        }
        return chapters
    }

    static func isHeading(_ line: String) -> Bool {
        if line.firstMatch(of: #/^(?i:chapter|book|part|letter|stave|canto)\s+(\d+|[IVXLCDMivxlcdm]+|[A-Za-z]+)\b/#) != nil {
            return true
        }
        if let match = line.firstMatch(of: #/^([IVXLCDM]+)\.?\s*$/#),
           RomanNumerals.parse(String(match.1)) != nil {
            return true
        }
        if line.firstMatch(of: #/^(\d+)\.?\s*$/#) != nil {
            return true
        }
        return false
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Test Suite 'All tests' passed`

Note the fourth test: `II.` appears mid-prose after a non-blank line (`See Act`), so the blank-line guard must reject it. If it fails, the guard is broken — do not loosen the test.

- [ ] **Step 5: Commit**

```bash
git add AudiobooksTV/Core/ChapterSplitter.swift Tests/AudiobooksCoreTests/ChapterSplitterTests.swift
git commit -m "feat: add chapter splitter for Gutenberg plain text"
```

---

### Task 5: SectionAligner

**Files:**
- Create: `AudiobooksTV/Core/SectionAligner.swift`
- Test: `Tests/AudiobooksCoreTests/SectionAlignerTests.swift`

**Interfaces:**
- Consumes: `RomanNumerals.parse`
- Produces:
  - `struct ChapterAlignment: Equatable { let chapterIndexBySection: [Int?]; var matchedCount: Int }`
  - `SectionAligner.normalize(_ title: String) -> String`
  - `SectionAligner.align(sectionTitles: [String], chapterTitles: [String]) -> ChapterAlignment`

Matching strategy, in order: exact normalized match → whitespace-padded containment (either direction) → if NOTHING matched and counts are equal, positional 1:1.

- [ ] **Step 1: Write the failing tests**

`Tests/AudiobooksCoreTests/SectionAlignerTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test 2>&1 | tail -5`
Expected: FAIL — `cannot find 'SectionAligner' in scope`

- [ ] **Step 3: Write the implementation**

`AudiobooksTV/Core/SectionAligner.swift`:

```swift
import Foundation

struct ChapterAlignment: Equatable {
    /// chapterIndexBySection[i] is the chapter index for audio section i,
    /// or nil when no text chapter matched.
    let chapterIndexBySection: [Int?]

    var matchedCount: Int { chapterIndexBySection.compactMap { $0 }.count }
}

enum SectionAligner {
    /// Lowercases, splits on non-alphanumerics, converts Roman-numeral tokens
    /// and zero-padded numbers to plain Arabic, rejoins with single spaces.
    static func normalize(_ title: String) -> String {
        let tokens = title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let mapped = tokens.map { token -> String in
            if let n = Int(token) { return String(n) }
            if token.allSatisfy({ "ivxlcdm".contains($0) }),
               let n = RomanNumerals.parse(String(token)) {
                return String(n)
            }
            return String(token)
        }
        return mapped.joined(separator: " ")
    }

    static func align(sectionTitles: [String], chapterTitles: [String]) -> ChapterAlignment {
        let chapters = chapterTitles.map(normalize)
        var result: [Int?] = []

        for sectionTitle in sectionTitles {
            let section = normalize(sectionTitle)
            if let exact = chapters.firstIndex(of: section) {
                result.append(exact)
                continue
            }
            // Padded containment so "chapter 1" can't match inside "chapter 12".
            let padded = " \(section) "
            let contained = chapters.firstIndex { chapter in
                guard !chapter.isEmpty else { return false }
                return padded.contains(" \(chapter) ") || " \(chapter) ".contains(padded)
            }
            result.append(contained)
        }

        if result.allSatisfy({ $0 == nil }), sectionTitles.count == chapterTitles.count {
            result = (0..<sectionTitles.count).map { $0 }
        }
        return ChapterAlignment(chapterIndexBySection: result)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 5: Commit**

```bash
git add AudiobooksTV/Core/SectionAligner.swift Tests/AudiobooksCoreTests/SectionAlignerTests.swift
git commit -m "feat: add section-to-chapter aligner"
```

---

### Task 6: Models + LibriVox JSON parsing

**Files:**
- Create: `AudiobooksTV/Core/Audiobook.swift`
- Create: `AudiobooksTV/Core/LibriVoxParser.swift`
- Test: `Tests/AudiobooksCoreTests/LibriVoxParserTests.swift`

**Interfaces:**
- Consumes: `GutenbergText.ebookID(fromTextSource:)`
- Produces:

```swift
struct Audiobook: Identifiable, Hashable {
    let id: Int
    let title: String
    let authors: String          // "Jane Austen", joined with ", "
    let description: String      // HTML tags stripped
    let genres: [String]
    let coverURL: URL?
    let textSourceURL: String?
    let totalTimeSeconds: Int
    let sections: [AudioSection]
    var gutenbergID: Int?        // computed
    var hasText: Bool            // computed: gutenbergID != nil
}

struct AudioSection: Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let listenURL: URL
    let playtimeSeconds: Int
}

enum LibriVoxParser {
    static func parseBooks(_ data: Data) throws -> [Audiobook]
    static func stripHTML(_ s: String) -> String
}
```

LibriVox API quirks the parser MUST handle: every numeric field arrives as a JSON **string** (`"id": "52"`, `"playtime": "1626"`); `url_text_source` may be null or empty; sections may be absent; cover comes from `coverart_jpg`, falling back to `https://archive.org/services/img/<identifier>` where `<identifier>` is the last path component of `url_iarchive`; an empty result set returns `{"error": "..."}` instead of `{"books": []}` — treat as empty array, not an error.

- [ ] **Step 1: Write the failing tests**

`Tests/AudiobooksCoreTests/LibriVoxParserTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test 2>&1 | tail -5`
Expected: FAIL — `cannot find 'LibriVoxParser' in scope`

- [ ] **Step 3: Write the models**

`AudiobooksTV/Core/Audiobook.swift`:

```swift
import Foundation

struct Audiobook: Identifiable, Hashable {
    let id: Int
    let title: String
    let authors: String
    let description: String
    let genres: [String]
    let coverURL: URL?
    let textSourceURL: String?
    let totalTimeSeconds: Int
    let sections: [AudioSection]

    var gutenbergID: Int? {
        textSourceURL.flatMap(GutenbergText.ebookID(fromTextSource:))
    }

    var hasText: Bool { gutenbergID != nil }
}

struct AudioSection: Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let listenURL: URL
    let playtimeSeconds: Int
}
```

- [ ] **Step 4: Write the parser**

`AudiobooksTV/Core/LibriVoxParser.swift`:

```swift
import Foundation

enum LibriVoxParser {
    struct Envelope: Decodable {
        let books: [BookDTO]?
        let error: String?
    }

    struct BookDTO: Decodable {
        let id: String
        let title: String?
        let description: String?
        let url_text_source: String?
        let url_iarchive: String?
        let coverart_jpg: String?
        let totaltimesecs: Int?
        let authors: [AuthorDTO]?
        let genres: [GenreDTO]?
        let sections: [SectionDTO]?
    }

    struct AuthorDTO: Decodable {
        let first_name: String?
        let last_name: String?
    }

    struct GenreDTO: Decodable {
        let name: String?
    }

    struct SectionDTO: Decodable {
        let id: String
        let section_number: String?
        let title: String?
        let listen_url: String?
        let playtime: String?
    }

    static func parseBooks(_ data: Data) throws -> [Audiobook] {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let dtos = envelope.books else { return [] }
        return dtos.compactMap(makeBook)
    }

    private static func makeBook(_ dto: BookDTO) -> Audiobook? {
        guard let id = Int(dto.id) else { return nil }

        let authorNames = (dto.authors ?? []).map { author in
            [author.first_name, author.last_name]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }.filter { !$0.isEmpty }

        let sections = (dto.sections ?? []).compactMap { section -> AudioSection? in
            guard let sectionID = Int(section.id),
                  let urlString = section.listen_url,
                  let url = URL(string: urlString) else { return nil }
            return AudioSection(
                id: sectionID,
                number: section.section_number.flatMap(Int.init) ?? 0,
                title: section.title ?? "Section",
                listenURL: url,
                playtimeSeconds: section.playtime.flatMap(Int.init) ?? 0
            )
        }

        return Audiobook(
            id: id,
            title: dto.title ?? "Untitled",
            authors: authorNames.joined(separator: ", "),
            description: stripHTML(dto.description ?? ""),
            genres: (dto.genres ?? []).compactMap(\.name),
            coverURL: coverURL(coverart: dto.coverart_jpg, iarchive: dto.url_iarchive),
            textSourceURL: dto.url_text_source?.isEmpty == false ? dto.url_text_source : nil,
            totalTimeSeconds: dto.totaltimesecs ?? 0,
            sections: sections
        )
    }

    private static func coverURL(coverart: String?, iarchive: String?) -> URL? {
        if let coverart, !coverart.isEmpty, let url = URL(string: coverart) {
            return url
        }
        if let iarchive,
           let identifier = URL(string: iarchive)?.lastPathComponent,
           !identifier.isEmpty {
            return URL(string: "https://archive.org/services/img/\(identifier)")
        }
        return nil
    }

    static func stripHTML(_ s: String) -> String {
        s.replacing(#/<[^>]+>/#, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 6: Build the app target, then commit**

Run the build check command; expected `BUILD SUCCEEDED`.

```bash
git add AudiobooksTV/Core/Audiobook.swift AudiobooksTV/Core/LibriVoxParser.swift Tests/AudiobooksCoreTests/LibriVoxParserTests.swift
git commit -m "feat: add Audiobook models and LibriVox response parser"
```

---

### Task 7: ProgressStore

**Files:**
- Create: `AudiobooksTV/Core/ProgressStore.swift`
- Test: `Tests/AudiobooksCoreTests/ProgressStoreTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:

```swift
struct PlaybackProgress: Codable, Equatable {
    let bookID: Int
    let bookTitle: String
    let coverURL: URL?
    let sectionIndex: Int
    let seconds: Double
    let updatedAt: Date
}

final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()
    @Published private(set) var items: [PlaybackProgress]   // newest first, max 20
    init(defaults: UserDefaults = .standard)
    func save(_ progress: PlaybackProgress)                  // upsert by bookID
    func progress(for bookID: Int) -> PlaybackProgress?
    func remove(bookID: Int)
}
```

- [ ] **Step 1: Write the failing tests**

`Tests/AudiobooksCoreTests/ProgressStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test 2>&1 | tail -5`
Expected: FAIL — `cannot find 'ProgressStore' in scope`

- [ ] **Step 3: Write the implementation**

`AudiobooksTV/Core/ProgressStore.swift`:

```swift
import Foundation
import Combine

struct PlaybackProgress: Codable, Equatable {
    let bookID: Int
    let bookTitle: String
    let coverURL: URL?
    let sectionIndex: Int
    let seconds: Double
    let updatedAt: Date
}

/// Persists per-book playback positions in UserDefaults.
/// Newest-first, capped at 20 books. Feeds the "Continue Listening" shelf.
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()
    private static let key = "playbackProgress.v1"
    private static let cap = 20

    @Published private(set) var items: [PlaybackProgress] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([PlaybackProgress].self, from: data) {
            items = decoded
        }
    }

    func save(_ progress: PlaybackProgress) {
        items.removeAll { $0.bookID == progress.bookID }
        items.insert(progress, at: 0)
        if items.count > Self.cap {
            items.removeLast(items.count - Self.cap)
        }
        persist()
    }

    func progress(for bookID: Int) -> PlaybackProgress? {
        items.first { $0.bookID == bookID }
    }

    func remove(bookID: Int) {
        items.removeAll { $0.bookID == bookID }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test 2>&1 | tail -3`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 5: Commit**

```bash
git add AudiobooksTV/Core/ProgressStore.swift Tests/AudiobooksCoreTests/ProgressStoreTests.swift
git commit -m "feat: add playback progress store"
```

---

### Task 8: LibriVoxClient (network + caches)

**Files:**
- Create: `AudiobooksTV/Services/LibriVoxClient.swift`
- Create: `AudiobooksTV/Core/Shelf.swift`

**Interfaces:**
- Consumes: `LibriVoxParser.parseBooks`, `Audiobook`, `AudioSection`
- Produces:

```swift
struct Shelf: Identifiable, Hashable {
    let id: String        // genre query value, e.g. "Detective Fiction"
    let title: String     // display, e.g. "Mystery"
    static let all: [Shelf]
}

enum LibriVoxError: LocalizedError { case requestFailed(Int) }

actor LibriVoxClient {
    static let shared = LibriVoxClient()
    func books(genre: String, limit: Int = 20) async throws -> [Audiobook]   // session-cached per genre
    func search(_ term: String) async throws -> [Audiobook]                  // title + author queries, merged, deduped
    func book(id: Int) async throws -> Audiobook?
    func audioFile(for section: AudioSection) async throws -> URL            // disk-cached mp3, prune keeping 20
}
```

No unit tests (network); verified by app build here and by simulator smoke test in Task 13.

- [ ] **Step 1: Write Shelf**

`AudiobooksTV/Core/Shelf.swift`:

```swift
import Foundation

struct Shelf: Identifiable, Hashable {
    let id: String
    let title: String

    /// Hardcoded home-screen shelves. `id` is the LibriVox genre name used in
    /// the API query; `title` is what the user sees.
    static let all: [Shelf] = [
        Shelf(id: "General Fiction", title: "Fiction"),
        Shelf(id: "Detective Fiction", title: "Mystery"),
        Shelf(id: "Science Fiction", title: "Sci-Fi"),
        Shelf(id: "Children's Fiction", title: "Children's"),
        Shelf(id: "History", title: "History"),
        Shelf(id: "Action & Adventure", title: "Adventure"),
        Shelf(id: "Poetry", title: "Poetry"),
    ]
}
```

- [ ] **Step 2: Write LibriVoxClient**

`AudiobooksTV/Services/LibriVoxClient.swift`:

```swift
import Foundation

enum LibriVoxError: LocalizedError {
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let code):
            return "LibriVox returned an error (HTTP \(code)). Check your network connection and try again."
        }
    }
}

/// Client for the LibriVox catalog API (https://librivox.org/api/feed/audiobooks).
/// Open API, no key. All audio files are hosted on archive.org.
actor LibriVoxClient {
    static let shared = LibriVoxClient()

    private var genreCache: [String: [Audiobook]] = [:]

    // MARK: Catalog

    func books(genre: String, limit: Int = 20) async throws -> [Audiobook] {
        if let cached = genreCache[genre] {
            return cached
        }
        let books = try await fetchBooks(queryItems: [
            .init(name: "genre", value: genre),
            .init(name: "limit", value: String(limit)),
        ])
        genreCache[genre] = books
        return books
    }

    func search(_ term: String) async throws -> [Audiobook] {
        async let byTitle = fetchBooks(queryItems: [.init(name: "title", value: term)])
        async let byAuthor = fetchBooks(queryItems: [.init(name: "author", value: term)])
        let (titles, authors) = try await (byTitle, byAuthor)

        var seen = Set<Int>()
        return (titles + authors).filter { seen.insert($0.id).inserted }
    }

    func book(id: Int) async throws -> Audiobook? {
        try await fetchBooks(queryItems: [.init(name: "id", value: String(id))]).first
    }

    private func fetchBooks(queryItems: [URLQueryItem]) async throws -> [Audiobook] {
        var components = URLComponents(string: "https://librivox.org/api/feed/audiobooks")!
        components.queryItems = queryItems + [
            .init(name: "format", value: "json"),
            .init(name: "extended", value: "1"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw LibriVoxError.requestFailed(http.statusCode)
        }
        return try LibriVoxParser.parseBooks(data)
    }

    // MARK: Audio download + cache

    /// Returns a local file URL for the section's MP3, downloading if needed.
    /// Keeps the 20 most recently played sections on disk.
    func audioFile(for section: AudioSection) async throws -> URL {
        let cacheURL = try audioCacheDirectory().appendingPathComponent("section-\(section.id).mp3")
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        let (data, response) = try await URLSession.shared.data(from: section.listenURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw LibriVoxError.requestFailed(http.statusCode)
        }
        try pruneAudioCache(keeping: 20)
        try data.write(to: cacheURL)
        return cacheURL
    }

    private func audioCacheDirectory() throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = caches.appendingPathComponent("LibriVoxAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func pruneAudioCache(keeping limit: Int) throws {
        let fm = FileManager.default
        let dir = try audioCacheDirectory()
        let files = try fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        )
        guard files.count >= limit else { return }

        let sorted = files.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
        for file in sorted.prefix(files.count - limit + 1) {
            try? fm.removeItem(at: file)
        }
    }
}
```

- [ ] **Step 3: Build**

Run the build check command.
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add AudiobooksTV/Services/LibriVoxClient.swift AudiobooksTV/Core/Shelf.swift
git commit -m "feat: add LibriVox API client with shelf and audio caches"
```

---

### Task 9: GutenbergClient

**Files:**
- Create: `AudiobooksTV/Services/GutenbergClient.swift`

**Interfaces:**
- Consumes: `GutenbergText.stripBoilerplate`
- Produces: `GutenbergClient.shared.fullText(ebookID: Int) async throws -> String` — boilerplate already stripped, disk-cached

- [ ] **Step 1: Write the client**

`AudiobooksTV/Services/GutenbergClient.swift`:

```swift
import Foundation

enum GutenbergError: LocalizedError {
    case notFound
    case undecodable

    var errorDescription: String? {
        switch self {
        case .notFound: return "The book text could not be found on Project Gutenberg."
        case .undecodable: return "The book text could not be decoded."
        }
    }
}

/// Fetches plain-text ebooks from Project Gutenberg and caches them on disk,
/// with the license boilerplate already stripped.
struct GutenbergClient {
    static let shared = GutenbergClient()

    func fullText(ebookID: Int) async throws -> String {
        let cacheURL = try textCacheDirectory().appendingPathComponent("pg\(ebookID).txt")
        if let cached = try? String(contentsOf: cacheURL, encoding: .utf8) {
            return cached
        }

        let candidates = [
            "https://www.gutenberg.org/cache/epub/\(ebookID)/pg\(ebookID).txt",
            "https://www.gutenberg.org/files/\(ebookID)/\(ebookID)-0.txt",
            "https://www.gutenberg.org/files/\(ebookID)/\(ebookID).txt",
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
            guard let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
                throw GutenbergError.undecodable
            }
            let text = GutenbergText.stripBoilerplate(raw)
            try? text.write(to: cacheURL, atomically: true, encoding: .utf8)
            return text
        }
        throw GutenbergError.notFound
    }

    private func textCacheDirectory() throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = caches.appendingPathComponent("GutenbergText", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
```

- [ ] **Step 2: Build**

Run the build check command.
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add AudiobooksTV/Services/GutenbergClient.swift
git commit -m "feat: add Gutenberg text client with disk cache"
```

---

### Task 10: BookTextModel

**Files:**
- Create: `AudiobooksTV/Services/BookTextModel.swift`

**Interfaces:**
- Consumes: `GutenbergClient.fullText`, `ChapterSplitter.split`, `SectionAligner.align`, `Audiobook`
- Produces:

```swift
@MainActor
final class BookTextModel: ObservableObject {
    enum State: Equatable { case idle, loading, unavailable(String), loaded }
    @Published private(set) var state: State
    @Published private(set) var chapters: [TextChapter]
    @Published private(set) var alignment: ChapterAlignment?
    var matchSummary: String?                              // "Read-along: 59 of 61 chapters matched"
    func load(book: Audiobook) async
    func chapter(forSectionIndex index: Int) -> TextChapter?  // nil = unmatched section
}
```

- [ ] **Step 1: Write the model**

`AudiobooksTV/Services/BookTextModel.swift`:

```swift
import Foundation

/// Loads a book's Gutenberg text, splits it into chapters, and aligns audio
/// sections to text chapters. One instance per opened book.
@MainActor
final class BookTextModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case unavailable(String)
        case loaded
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var chapters: [TextChapter] = []
    @Published private(set) var alignment: ChapterAlignment?

    var matchSummary: String? {
        guard case .loaded = state, let alignment else { return nil }
        return "Read-along: \(alignment.matchedCount) of \(alignment.chapterIndexBySection.count) chapters matched"
    }

    func load(book: Audiobook) async {
        guard state == .idle else { return }
        guard let ebookID = book.gutenbergID else {
            state = .unavailable("Text unavailable for this book.")
            return
        }
        state = .loading
        do {
            let text = try await GutenbergClient.shared.fullText(ebookID: ebookID)
            let chapters = ChapterSplitter.split(text)
            self.chapters = chapters
            self.alignment = SectionAligner.align(
                sectionTitles: book.sections.map(\.title),
                chapterTitles: chapters.map(\.title)
            )
            state = .loaded
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    /// The matched text chapter for an audio section, or nil when unmatched
    /// (caller falls back to the whole-book scroll).
    func chapter(forSectionIndex index: Int) -> TextChapter? {
        guard let alignment,
              index < alignment.chapterIndexBySection.count,
              let chapterIndex = alignment.chapterIndexBySection[index],
              chapterIndex < chapters.count else { return nil }
        return chapters[chapterIndex]
    }
}
```

- [ ] **Step 2: Build**

Run the build check command.
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add AudiobooksTV/Services/BookTextModel.swift
git commit -m "feat: add book text model orchestrating fetch, split, align"
```

---

### Task 11: Browse views — HomeView, shelf rows, cards, SearchView

**Files:**
- Create: `AudiobooksTV/Views/BookCardView.swift`
- Create: `AudiobooksTV/Views/ShelfRowView.swift`
- Create: `AudiobooksTV/Views/HomeView.swift`
- Create: `AudiobooksTV/Views/SearchView.swift`

**Interfaces:**
- Consumes: `LibriVoxClient.books/search/book(id:)`, `Shelf.all`, `ProgressStore.shared`, `Audiobook.hasText`
- Produces: `HomeView` (new root view), `BookCardView(book:)`, `ShelfRowView(shelf:readAlongOnly:)`, `SearchView`. All navigation pushes `BookDetailView(book:)` — created in Task 12; until then use a placeholder noted in Step 5.
- Text-availability UX: card title in `.primary` color when `book.hasText`, `.secondary` when audio-only. `@AppStorage("readAlongOnly")` filter toggle lives on HomeView toolbar and SearchView.

- [ ] **Step 1: Write BookCardView**

`AudiobooksTV/Views/BookCardView.swift`:

```swift
import SwiftUI

struct BookCardView: View {
    let book: Audiobook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: book.coverURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "book.closed")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 280, height: 280)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(book.title)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(book.hasText ? .primary : .secondary)

            Text(book.authors)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 280)
    }
}
```

- [ ] **Step 2: Write ShelfRowView**

`AudiobooksTV/Views/ShelfRowView.swift`:

```swift
import SwiftUI

struct ShelfRowView: View {
    let shelf: Shelf
    let readAlongOnly: Bool

    @State private var books: [Audiobook] = []
    @State private var failed = false

    private var visibleBooks: [Audiobook] {
        readAlongOnly ? books.filter(\.hasText) : books
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.title)
                .font(.title3.bold())
                .padding(.leading, 64)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    if books.isEmpty && !failed {
                        ProgressView()
                            .frame(height: 280)
                    }
                    if failed {
                        Text("Couldn't load this shelf.")
                            .foregroundStyle(.secondary)
                            .frame(height: 280)
                    }
                    ForEach(visibleBooks) { book in
                        NavigationLink(value: book) {
                            BookCardView(book: book)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 24)
            }
        }
        .task {
            guard books.isEmpty else { return }
            do {
                books = try await LibriVoxClient.shared.books(genre: shelf.id)
            } catch {
                failed = true
            }
        }
    }
}
```

- [ ] **Step 3: Write HomeView (with Continue Listening row)**

`AudiobooksTV/Views/HomeView.swift`:

```swift
import SwiftUI

struct HomeView: View {
    @AppStorage("readAlongOnly") private var readAlongOnly = false
    @ObservedObject private var progressStore = ProgressStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if !progressStore.items.isEmpty {
                    continueListeningRow
                }
                ForEach(Shelf.all) { shelf in
                    ShelfRowView(shelf: shelf, readAlongOnly: readAlongOnly)
                }
            }
            .padding(.vertical, 32)
        }
        .navigationTitle("Audiobooks")
        .navigationDestination(for: Audiobook.self) { book in
            BookDetailView(book: book)
        }
        .navigationDestination(for: PlaybackProgress.self) { progress in
            BookByIDView(bookID: progress.bookID)
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle("Read-along only", isOn: $readAlongOnly)
                NavigationLink {
                    SearchView()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
    }

    private var continueListeningRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Listening")
                .font(.title3.bold())
                .padding(.leading, 64)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    ForEach(progressStore.items, id: \.bookID) { progress in
                        NavigationLink(value: progress) {
                            VStack(alignment: .leading, spacing: 8) {
                                AsyncImage(url: progress.coverURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    default:
                                        Rectangle().fill(.quaternary)
                                    }
                                }
                                .frame(width: 280, height: 280)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                                Text(progress.bookTitle)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                            .frame(width: 280)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 24)
            }
        }
    }
}

/// Fetches a book by LibriVox id, then shows its detail view.
/// Used by Continue Listening, which only persists the id.
struct BookByIDView: View {
    let bookID: Int

    @State private var book: Audiobook?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let book {
                BookDetailView(book: book)
            } else if let errorMessage {
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text(errorMessage)
                    Button("Try Again") {
                        self.errorMessage = nil
                        Task { await load() }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            if let fetched = try await LibriVoxClient.shared.book(id: bookID) {
                book = fetched
            } else {
                errorMessage = "This book is no longer available."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Write SearchView**

`AudiobooksTV/Views/SearchView.swift`:

```swift
import SwiftUI

struct SearchView: View {
    @AppStorage("readAlongOnly") private var readAlongOnly = false

    @State private var query = ""
    @State private var results: [Audiobook] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 32)]

    private var visibleResults: [Audiobook] {
        readAlongOnly ? results.filter(\.hasText) : results
    }

    var body: some View {
        ScrollView {
            if isSearching {
                ProgressView("Searching…")
                    .padding(.top, 120)
            } else if let errorMessage {
                VStack(spacing: 24) {
                    Text(errorMessage)
                    Button("Try Again") { Task { await search() } }
                }
                .padding(.top, 120)
            } else {
                LazyVGrid(columns: columns, spacing: 48) {
                    ForEach(visibleResults) { book in
                        NavigationLink(value: book) {
                            BookCardView(book: book)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(64)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Title or author")
        .toolbar {
            Toggle("Read-along only", isOn: $readAlongOnly)
        }
        .onSubmit(of: .search) {
            Task { await search() }
        }
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        do {
            results = try await LibriVoxClient.shared.search(term)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }
}
```

- [ ] **Step 5: Temporary BookDetailView stub so this task builds**

Create `AudiobooksTV/Views/BookDetailView.swift` with a stub that Task 12 fully replaces:

```swift
import SwiftUI

struct BookDetailView: View {
    let book: Audiobook

    var body: some View {
        Text(book.title)
    }
}
```

- [ ] **Step 6: Build**

Run the build check command.
Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Commit**

```bash
git add AudiobooksTV/Views
git commit -m "feat: add home shelves, continue listening, search views"
```

---

### Task 12: BookDetailView + PlayerView + app entry, delete Bible-era code

**Files:**
- Modify: `AudiobooksTV/Views/BookDetailView.swift` (replace stub entirely)
- Create: `AudiobooksTV/Views/PlayerView.swift`
- Modify: `AudiobooksTV/AudiobooksTVApp.swift`
- Delete: `AudiobooksTV/Support/Secrets.swift`, `AudiobooksTV/Views/SetupView.swift`, `AudiobooksTV/Views/BookListView.swift`, `AudiobooksTV/Views/ChapterGridView.swift`, `AudiobooksTV/Views/ReaderView.swift`, `AudiobooksTV/Models/BibleBook.swift`, `AudiobooksTV/Services/ESVClient.swift`

**Interfaces:**
- Consumes: `BookTextModel`, `AudioPlayerModel` (unchanged from BibleTV), `LibriVoxClient.audioFile(for:)`, `ProgressStore.shared`
- Produces: `BookDetailView(book:)`, `PlayerView(book:textModel:startSectionIndex:startSeconds:)`, app root = `HomeView`

- [ ] **Step 1: Replace BookDetailView**

Full contents of `AudiobooksTV/Views/BookDetailView.swift`:

```swift
import SwiftUI

struct BookDetailView: View {
    let book: Audiobook

    @StateObject private var textModel = BookTextModel()
    @State private var playTarget: PlayTarget?

    private struct PlayTarget: Identifiable, Hashable {
        let id = UUID()
        let sectionIndex: Int
        let seconds: Double
    }

    private var savedProgress: PlaybackProgress? {
        ProgressStore.shared.progress(for: book.id)
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 48) {
                AsyncImage(url: book.coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Rectangle().fill(.quaternary)
                    }
                }
                .frame(width: 400, height: 400)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 16) {
                    Text(book.title).font(.title2.bold())
                    Text(book.authors).font(.title3).foregroundStyle(.secondary)

                    switch textModel.state {
                    case .loading, .idle:
                        Label("Checking read-along text…", systemImage: "text.book.closed")
                            .foregroundStyle(.secondary)
                    case .loaded:
                        Label(textModel.matchSummary ?? "Read-along available",
                              systemImage: "text.book.closed.fill")
                    case .unavailable:
                        Label("Text unavailable — audio only", systemImage: "headphones")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        if let saved = savedProgress {
                            playTarget = PlayTarget(sectionIndex: saved.sectionIndex, seconds: saved.seconds)
                        } else {
                            playTarget = PlayTarget(sectionIndex: 0, seconds: 0)
                        }
                    } label: {
                        Label(savedProgress == nil ? "Play" : "Resume",
                              systemImage: "play.fill")
                    }
                    .disabled(book.sections.isEmpty)

                    if !book.description.isEmpty {
                        Text(book.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                    }
                }
                Spacer()
            }
            .padding(64)

            VStack(alignment: .leading, spacing: 8) {
                Text("Chapters").font(.title3.bold())
                ForEach(Array(book.sections.enumerated()), id: \.element.id) { index, section in
                    Button {
                        playTarget = PlayTarget(sectionIndex: index, seconds: 0)
                    } label: {
                        HStack {
                            Text(section.title)
                            Spacer()
                            Text(timeString(section.playtimeSeconds))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(.horizontal, 64)
            .padding(.bottom, 48)
        }
        .navigationTitle(book.title)
        .task {
            await textModel.load(book: book)
        }
        .fullScreenCover(item: $playTarget) { target in
            PlayerView(
                book: book,
                textModel: textModel,
                startSectionIndex: target.sectionIndex,
                startSeconds: target.seconds
            )
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
```

- [ ] **Step 2: Write PlayerView**

`AudiobooksTV/Views/PlayerView.swift`:

```swift
import SwiftUI

/// Read-along player: chapter text on screen, audio narrating, auto-advance.
struct PlayerView: View {
    let book: Audiobook
    @ObservedObject var textModel: BookTextModel
    let startSectionIndex: Int
    let startSeconds: Double

    @Environment(\.dismiss) private var dismiss
    @StateObject private var audio = AudioPlayerModel()

    @State private var sectionIndex: Int
    @State private var isLoadingAudio = false
    @State private var errorMessage: String?
    @State private var autoAdvance = true
    @State private var pendingSeekSeconds: Double
    @State private var lastSavedSeconds: Double = 0

    init(book: Audiobook, textModel: BookTextModel, startSectionIndex: Int, startSeconds: Double) {
        self.book = book
        self.textModel = textModel
        self.startSectionIndex = startSectionIndex
        self.startSeconds = startSeconds
        _sectionIndex = State(initialValue: startSectionIndex)
        _pendingSeekSeconds = State(initialValue: startSeconds)
    }

    private var section: AudioSection { book.sections[sectionIndex] }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
                .padding(.horizontal, 64)
                .padding(.vertical, 24)

            progressBar
                .padding(.horizontal, 64)
                .padding(.bottom, 16)

            Divider()

            textBody

        }
        .navigationTitle(section.title)
        .task(id: sectionIndex) {
            await startAudio()
        }
        .onChange(of: audio.currentTime) { _, newTime in
            if abs(newTime - lastSavedSeconds) > 15 {
                saveProgress(seconds: newTime)
            }
        }
        .onDisappear {
            saveProgress(seconds: audio.currentTime)
            audio.stop()
        }
    }

    // MARK: Controls

    private var controlBar: some View {
        HStack(spacing: 24) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
            }

            Button {
                sectionIndex -= 1
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .disabled(sectionIndex <= 0)

            Button {
                audio.togglePlayPause()
                if !audio.isPlaying {
                    saveProgress(seconds: audio.currentTime)
                }
            } label: {
                if isLoadingAudio {
                    ProgressView()
                } else {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                }
            }
            .disabled(isLoadingAudio)

            Button {
                sectionIndex += 1
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .disabled(sectionIndex >= book.sections.count - 1)

            Spacer()

            Text(book.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                audio.cycleRate()
            } label: {
                Text(String(format: "%g×", audio.rate))
                    .monospacedDigit()
            }

            Button {
                autoAdvance.toggle()
            } label: {
                Label("Auto-advance", systemImage: autoAdvance ? "text.line.first.and.arrowtriangle.forward" : "stop.circle")
                    .labelStyle(.iconOnly)
            }
            .foregroundStyle(autoAdvance ? .primary : .tertiary)
        }
        .font(.title3)
    }

    private var progressBar: some View {
        HStack(spacing: 16) {
            Text(timeString(audio.currentTime))
            ProgressView(value: min(audio.currentTime, audio.duration), total: max(audio.duration, 1))
            Text(timeString(audio.duration))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    // MARK: Text

    @ViewBuilder
    private var textBody: some View {
        if let errorMessage {
            Spacer()
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                Button("Try Again") {
                    self.errorMessage = nil
                    Task { await startAudio() }
                }
            }
            Spacer()
        } else if let chapter = textModel.chapter(forSectionIndex: sectionIndex) {
            chapterScroll([chapter], header: nil)
        } else if case .loaded = textModel.state {
            // Section didn't align — whole-book fallback.
            chapterScroll(textModel.chapters, header: "This chapter couldn't be matched — showing the full book text.")
        } else {
            // No text at all: cover-only player.
            Spacer()
            VStack(spacing: 24) {
                AsyncImage(url: book.coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    default:
                        Image(systemName: "book.closed").font(.system(size: 120))
                    }
                }
                .frame(maxHeight: 500)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Text("Text unavailable for this book")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func chapterScroll(_ chapters: [TextChapter], header: String?) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if let header {
                    Text(header)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(chapters.enumerated()), id: \.offset) { _, chapter in
                    if chapters.count > 1 {
                        Text(chapter.title)
                            .font(.system(size: 30, weight: .semibold, design: .serif))
                    }
                    Text(chapter.body)
                        .font(.system(size: 38, design: .serif))
                        .focusable()
                }
            }
            .frame(maxWidth: 1200, alignment: .leading)
            .padding(.horizontal, 64)
            .padding(.vertical, 48)
        }
    }

    // MARK: Actions

    private func startAudio() async {
        isLoadingAudio = true
        defer { isLoadingAudio = false }
        do {
            let fileURL = try await LibriVoxClient.shared.audioFile(for: section)
            audio.onChapterFinished = sectionFinished
            audio.load(fileURL: fileURL, autoplay: true)
            if pendingSeekSeconds > 0 {
                audio.skip(by: pendingSeekSeconds)
                pendingSeekSeconds = 0
            }
            saveProgress(seconds: audio.currentTime)
        } catch is CancellationError {
            // View went away; nothing to do.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sectionFinished() {
        guard autoAdvance, sectionIndex < book.sections.count - 1 else { return }
        sectionIndex += 1
    }

    private func saveProgress(seconds: Double) {
        lastSavedSeconds = seconds
        ProgressStore.shared.save(PlaybackProgress(
            bookID: book.id,
            bookTitle: book.title,
            coverURL: book.coverURL,
            sectionIndex: sectionIndex,
            seconds: seconds,
            updatedAt: Date()
        ))
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 3: Point the app at HomeView and delete Bible-era files**

Replace `AudiobooksTV/AudiobooksTVApp.swift` contents:

```swift
import SwiftUI

@main
struct AudiobooksTVApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                HomeView()
            }
        }
    }
}
```

```bash
git rm AudiobooksTV/Support/Secrets.swift \
       AudiobooksTV/Views/SetupView.swift \
       AudiobooksTV/Views/BookListView.swift \
       AudiobooksTV/Views/ChapterGridView.swift \
       AudiobooksTV/Views/ReaderView.swift \
       AudiobooksTV/Models/BibleBook.swift \
       AudiobooksTV/Services/ESVClient.swift
rmdir AudiobooksTV/Support AudiobooksTV/Models 2>/dev/null || true
```

(`AudioPlayerModel.swift` stays — reused unchanged.)

- [ ] **Step 4: Build and run tests**

Run the build check command — expected `BUILD SUCCEEDED`.
Run `swift test 2>&1 | tail -3` — expected `Test Suite 'All tests' passed`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add book detail and read-along player, remove Bible-era code"
```

---

### Task 13: Simulator smoke test

**Files:** none created; fixes go wherever the smoke test finds problems.

**Interfaces:**
- Consumes: the whole app
- Produces: verified v1

- [ ] **Step 1: Boot the app in the simulator**

```bash
xcrun simctl boot "Apple TV" 2>/dev/null || true
xcodebuild -project AudiobooksTV.xcodeproj -scheme AudiobooksTV \
  -destination 'platform=tvOS Simulator,name=Apple TV' build
APP=$(find ~/Library/Developer/Xcode/DerivedData -path '*appletvsimulator*/AudiobooksTV.app' | head -1)
xcrun simctl install "Apple TV" "$APP"
xcrun simctl launch "Apple TV" com.jonyen.AudiobooksTV
open -a Simulator
```

- [ ] **Step 2: Walk the smoke checklist from the spec**

1. Home loads shelves with covers; audio-only titles render dimmed.
2. "Read-along only" toggle hides audio-only books.
3. Search for "Pride and Prejudice" returns results.
4. Open it: detail shows "Read-along: N of M chapters matched"; Play starts audio; chapter text displays; speed control cycles.
5. Skip to next chapter: text and audio both advance. Let a chapter finish (seek near the end): auto-advance fires.
6. Kill and relaunch app: Continue Listening row shows the book; tapping resumes at the saved section/position.
7. Find an audio-only book (toggle filter off, look for a dimmed title): player shows cover + "Text unavailable for this book".

Record any failure, apply the smallest fix, rebuild, re-verify that item, and re-run `swift test`.

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: smoke test fixes"
```

(Skip the commit if nothing changed.)

---

### Task 14: README + push

**Files:**
- Modify: `README.md` (full rewrite)

**Interfaces:**
- Consumes: nothing
- Produces: accurate README; branch pushed

- [ ] **Step 1: Rewrite README.md**

Replace the full contents of `README.md` with:

```markdown
# AudiobooksTV — Read-Along Audiobooks for Apple TV

A SwiftUI Apple TV app that plays free public-domain audiobooks from
[LibriVox](https://librivox.org) while showing the matching book text from
[Project Gutenberg](https://www.gutenberg.org) on screen — listen and read
along, chapter by chapter.

Derived from [bible-appletv](https://github.com/jonyen/bible-appletv).

## Features

- **Browse** curated genre shelves (Fiction, Mystery, Sci-Fi, Children's,
  History, Adventure, Poetry) or search ~45,000 titles by title/author
- **Read along**: chapter text on screen while the narration plays, with
  play/pause, 0.75×–1.5× speed, and auto-advance to the next chapter
- **Text-availability at a glance**: dimmed titles are audio-only; a
  "Read-along only" toggle filters them out
- **Continue Listening**: playback position is saved per book and resumable
  from the home screen
- Recently played chapters and book texts are cached on-device

## How text matching works

LibriVox book records link to their Project Gutenberg source text. The app
downloads the plain text, strips the Gutenberg license boilerplate, splits it
into chapters by heading detection, and aligns audio sections to text
chapters by normalized title matching (Roman numerals → Arabic, punctuation
stripped), with positional fallback. The detail screen reports how many
chapters matched. Unmatched chapters fall back to a whole-book text scroll;
books with no Gutenberg source play audio-only.

## Setup

No API keys. Open `AudiobooksTV.xcodeproj` in Xcode 16 or later, select the
*AudiobooksTV* scheme and an Apple TV simulator (or device), and run.

Run the logic tests with `swift test` (macOS, no simulator needed).

## Project layout

```
AudiobooksTV/
├── AudiobooksTVApp.swift       App entry point
├── Core/                       Pure logic — also built as an SPM target for tests
│   ├── Audiobook.swift         Audiobook + AudioSection models
│   ├── LibriVoxParser.swift    LibriVox JSON → models
│   ├── GutenbergText.swift     Ebook ID extraction, boilerplate stripping
│   ├── ChapterSplitter.swift   Plain text → chapters
│   ├── SectionAligner.swift    Audio sections ↔ text chapters
│   ├── RomanNumerals.swift     Roman numeral parsing
│   ├── ProgressStore.swift     Saved playback positions
│   └── Shelf.swift             Home-screen genre shelves
├── Services/
│   ├── LibriVoxClient.swift    Catalog API + MP3 download/cache
│   ├── GutenbergClient.swift   Text download/cache
│   ├── BookTextModel.swift     Fetch → split → align orchestration
│   └── AudioPlayerModel.swift  AVPlayer wrapper
└── Views/
    ├── HomeView.swift          Shelves + Continue Listening
    ├── SearchView.swift        Title/author search
    ├── BookDetailView.swift    Book info, chapters, match summary
    ├── PlayerView.swift        Read-along player
    ├── ShelfRowView.swift      Horizontal book row
    └── BookCardView.swift      Cover card with text-availability tint
```

## Content licensing

All audio (LibriVox) and text (Project Gutenberg) is in the public domain.
```

- [ ] **Step 2: Commit and push**

```bash
git add README.md
git commit -m "docs: rewrite README for AudiobooksTV"
git push origin main
```

---

## Self-Review Notes

- Spec coverage: shelves+search (T8, T11), text-availability tint + filter (T11), text pipeline (T3–T5, T9, T10), read-along player with fallbacks (T12), Continue Listening/resume (T7, T11, T12), match summary (T10, T12), rename/repo (T1), smoke checklist (T13). Cover fallback chain (T6). No gaps found.
- Types cross-checked: `ChapterAlignment` (not `Alignment` — avoids clash with SwiftUI.Alignment), `TextChapter`, `PlaybackProgress`, `AudioSection` names consistent across tasks.
- `AudioPlayerModel` is intentionally untouched; `AVAudioSession` exists on tvOS.
