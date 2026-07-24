# Hiding Books Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user hide books they'll never want so Home shelves stop showing them, synced between the tvOS app and the web app.

**Architecture:** Hiding reuses the mark/tombstone pattern already proven for finished sections. Two new maps — `hiddenMarks` and `unhiddenMarks`, keyed by book ID — join the existing `users/{uid}/state/progress` document and merge by per-key maximum, so no new document, listener, or merge machinery is needed. Each platform filters hidden books out of its shelf rows only; search keeps showing them, marked, which doubles as the unhide path.

**Tech Stack:** TypeScript + React + Vitest (web); Swift + XCTest (tvOS Core, `swift test`); Firebase Firestore on both.

**Spec:** `docs/superpowers/specs/2026-07-24-hide-books-design.md`

## Global Constraints

- Hidden-map keys are the book ID alone (`"52"`), matching the `positions` map. Section keys stay `"<bookID>#<sectionIndex>"` — do not reuse them for hiding.
- A book is hidden iff its `hiddenMarks` entry is newer than any `unhiddenMarks` entry for the same key. Marks are never deleted; merging takes the per-key maximum.
- Timestamps are ms-epoch numbers (`Date.now()` / `Date().timeIntervalSince1970 * 1000`).
- Writes are field-level merges on a single top-level field (`setDoc(..., {merge: true})` / `setData(..., merge: true)`).
- Hiding never touches positions or finished marks. Continue Listening keeps showing a hidden book you've started.
- Shelf rows filter client-side after the LibriVox fetch; do NOT page the API to backfill a shortened row.
- tvOS: pure logic lives in `AudiobooksTV/Core/` (SPM target `AudiobooksCore`, no Firebase imports); Firebase glue stays in `AudiobooksTV/Services/`.
- tvOS store hooks fire for user actions only — never from `applyRemote`, or remote changes echo back as new writes.
- Web commands run from `web/`; Swift logic tests run with `swift test` from the repo root.
- Commit after every task; commit messages end with the standard co-author trailer.

---

### Task 1: Web — hidden marks in the merge layer

**Files:**
- Modify: `web/src/lib/progressMerge.ts`
- Test: `web/src/lib/progressMerge.test.ts`

**Interfaces:**
- Produces:
  - `ProgressState` gains `hiddenMarks: Record<string, number>` and `unhiddenMarks: Record<string, number>`
  - `bookKey(bookID: number): string` — `"52"`
  - `isHidden(state: ProgressState, bookID: number): boolean`
  - `mergeProgress` carries both new maps through the existing `maxByKey`
  - `emptyProgress()` seeds both maps

- [ ] **Step 1: Write the failing tests**

Add to the end of `web/src/lib/progressMerge.test.ts`, and extend its import list at the top of the file to include `bookKey` and `isHidden` alongside the existing imports:

```ts
test("bookKey matches the positions map key format", () => {
  expect(bookKey(52)).toBe("52");
});

test("isHidden: mark alone hides; newer unhide wins; newer re-hide wins back", () => {
  expect(isHidden(emptyProgress(), 52)).toBe(false);
  expect(isHidden(state({ hiddenMarks: { "52": 100 } }), 52)).toBe(true);
  const unhidden = state({ hiddenMarks: { "52": 100 }, unhiddenMarks: { "52": 200 } });
  expect(isHidden(unhidden, 52)).toBe(false);
  const rehidden = state({ hiddenMarks: { "52": 300 }, unhiddenMarks: { "52": 200 } });
  expect(isHidden(rehidden, 52)).toBe(true);
});

test("merge unions hidden marks taking per-key maximums", () => {
  const a = state({ hiddenMarks: { "1": 100, "52": 300 }, unhiddenMarks: { "52": 200 } });
  const b = state({ hiddenMarks: { "2": 150, "52": 250 }, unhiddenMarks: { "52": 400 } });
  const merged = mergeProgress(a, b);
  expect(merged.hiddenMarks).toEqual({ "1": 100, "2": 150, "52": 300 });
  expect(merged.unhiddenMarks).toEqual({ "52": 400 });
  expect(isHidden(merged, 1)).toBe(true);
  expect(isHidden(merged, 52)).toBe(false); // unhide at 400 beats re-hide at 300
});

test("stale unhide cannot resurrect a newer hide through merge", () => {
  const a = state({ hiddenMarks: { "52": 300 }, unhiddenMarks: { "52": 200 } });
  const b = state({ hiddenMarks: { "52": 100 }, unhiddenMarks: { "52": 200 } });
  expect(isHidden(mergeProgress(a, b), 52)).toBe(true);
});

test("hiding a book leaves its position and finished marks untouched", () => {
  const merged = mergeProgress(
    state({
      positions: { "52": pos(52, 100, 42) },
      finishedMarks: { "52#3": 100 },
      hiddenMarks: { "52": 500 },
    }),
    emptyProgress()
  );
  expect(merged.positions["52"].seconds).toBe(42);
  expect(merged.finishedMarks["52#3"]).toBe(100);
  expect(isHidden(merged, 52)).toBe(true);
});
```

(The file already defines the `state()` and `pos()` helpers these tests use.)

- [ ] **Step 2: Run to verify failure**

Run: `cd web && npm test`
Expected: FAIL — `bookKey` and `isHidden` are not exported from `./progressMerge`.

- [ ] **Step 3: Implement**

In `web/src/lib/progressMerge.ts`, extend the state interface and its constructor:

```ts
export interface ProgressState {
  positions: Record<string, PlaybackPosition>;
  finishedMarks: Record<string, number>;
  unfinishedMarks: Record<string, number>;
  hiddenMarks: Record<string, number>;
  unhiddenMarks: Record<string, number>;
}

export function emptyProgress(): ProgressState {
  return {
    positions: {},
    finishedMarks: {},
    unfinishedMarks: {},
    hiddenMarks: {},
    unhiddenMarks: {},
  };
}
```

Add these two functions immediately after `sectionKey`:

```ts
/** Key for the per-book hidden maps; matches the `positions` map's keys. */
export function bookKey(bookID: number): string {
  return String(bookID);
}

/**
 * A book is hidden iff its hide mark is newer than any unhide mark — the
 * same mark/tombstone rule as finished sections, so hide and unhide
 * converge across devices without either side resurrecting the other.
 */
export function isHidden(state: ProgressState, bookID: number): boolean {
  const key = bookKey(bookID);
  const hidden = state.hiddenMarks[key];
  if (hidden === undefined) return false;
  const unhidden = state.unhiddenMarks[key];
  return unhidden === undefined || hidden > unhidden;
}
```

Extend `mergeProgress`'s returned object with the two new maps (leave `positions`, `finishedMarks`, and `unfinishedMarks` exactly as they are):

```ts
  return {
    positions,
    finishedMarks: maxByKey(a.finishedMarks, b.finishedMarks),
    unfinishedMarks: maxByKey(a.unfinishedMarks, b.unfinishedMarks),
    hiddenMarks: maxByKey(a.hiddenMarks, b.hiddenMarks),
    unhiddenMarks: maxByKey(a.unhiddenMarks, b.unhiddenMarks),
  };
```

Finally, replace the file's top doc comment (lines 1–8) so it describes hiding too:

```ts
/**
 * Synced listening progress. Positions are last-writer-wins per book by
 * updatedAt. Finished sections and hidden books are mark/tombstone sets: a
 * section is finished iff its finishedMarks timestamp is newer than any
 * unfinishedMarks timestamp for the same key, and a book is hidden by the
 * same rule keyed on book ID alone. Marks are never deleted, so merging any
 * two device states always converges without resurrecting undone changes.
 */
```

- [ ] **Step 4: Run to verify pass**

Run: `cd web && npm test && npx tsc --noEmit`
Expected: all tests PASS (the 5 new ones plus every existing suite), typecheck clean.

- [ ] **Step 5: Commit**

```bash
git add web/src/lib/progressMerge.ts web/src/lib/progressMerge.test.ts
git commit -m "feat: hidden-book marks in the web merge layer"
```

---

### Task 2: Web — hide/unhide in the store and UI

**Files:**
- Modify: `web/src/lib/progress.ts`, `web/src/App.tsx`, `web/src/components/Home.tsx`, `web/src/components/Search.tsx`, `web/src/components/BookCard.tsx`, `web/src/components/BookDetail.tsx`, `web/src/styles.css`

**Interfaces:**
- Consumes: `bookKey`, `isHidden`, `ProgressState` (Task 1).
- Produces:
  - `Progress` interface gains `isHidden(bookID: number): boolean` and `toggleHidden(bookID: number): void`
  - `BookCard` props become `{ book: Audiobook; hidden?: boolean; onToggleHidden?: (bookID: number) => void }`
  - `Search` takes a `progress: Progress` prop

- [ ] **Step 1: Extend the store** — `web/src/lib/progress.ts`

Add `bookKey` and `isHidden as stateIsHidden` to the existing import from `./progressMerge`. Extend the interface:

```ts
export interface Progress {
  /** Continue Listening list: newest-first, capped at 20. */
  list: PlaybackPosition[];
  positionFor(bookID: number): PlaybackPosition | null;
  savePosition(p: Omit<PlaybackPosition, "updatedAt">): void;
  isFinished(bookID: number, sectionIndex: number): boolean;
  markFinished(bookID: number, sectionIndex: number): void;
  toggleFinished(bookID: number, sectionIndex: number): void;
  /** Hidden books drop out of Home shelves; search still shows them. */
  isHidden(bookID: number): boolean;
  toggleHidden(bookID: number): void;
}
```

Read the two new maps in the snapshot handler:

```ts
      const remote: ProgressState = {
        positions: positionsFromSnapshot((data as Record<string, unknown>).positions),
        finishedMarks: data.finishedMarks ?? {},
        unfinishedMarks: data.unfinishedMarks ?? {},
        hiddenMarks: data.hiddenMarks ?? {},
        unhiddenMarks: data.unhiddenMarks ?? {},
      };
```

Widen `writeMark`'s field union:

```ts
  const writeMark = useCallback(
    (
      field: "finishedMarks" | "unfinishedMarks" | "hiddenMarks" | "unhiddenMarks",
      key: string
    ) => {
```

And add the two methods to the returned object, after `toggleFinished`:

```ts
      isHidden: (bookID) => stateIsHidden(state, bookID),
      toggleHidden: (bookID) => {
        const hidden = stateIsHidden(state, bookID);
        writeMark(hidden ? "unhiddenMarks" : "hiddenMarks", bookKey(bookID));
      },
```

- [ ] **Step 2: Give the card a hide control** — replace `web/src/components/BookCard.tsx` entirely:

```tsx
import { Link } from "react-router-dom";
import type { Audiobook } from "../lib/librivox";
import { hasText } from "../lib/gutenberg";

/**
 * Cover card; audio-only books (no Gutenberg text) render dimmed, as on
 * tvOS. `hidden` is only ever true in search results — Home filters hidden
 * books out entirely — and marks the card so it can be unhidden from there.
 */
export default function BookCard({
  book,
  hidden = false,
  onToggleHidden,
}: {
  book: Audiobook;
  hidden?: boolean;
  onToggleHidden?: (bookID: number) => void;
}) {
  return (
    <div className={`card-wrap${hidden ? " card-hidden" : ""}`}>
      <Link to={`/book/${book.id}`} className={`card${hasText(book) ? "" : " card-dimmed"}`}>
        {book.coverURL ? (
          <img src={book.coverURL} alt="" loading="lazy" />
        ) : (
          <div className="card-placeholder">📖</div>
        )}
        <span className="card-title">{book.title}</span>
        <span className="card-authors">{book.authors}</span>
      </Link>
      {hidden && <span className="card-badge">Hidden</span>}
      {onToggleHidden && (
        <button
          type="button"
          className="card-hide"
          title={hidden ? "Unhide this book" : "Hide this book"}
          onClick={(event) => {
            event.preventDefault();
            onToggleHidden(book.id);
          }}
        >
          {hidden ? "↺" : "✕"}
        </button>
      )}
    </div>
  );
}
```

- [ ] **Step 3: Filter shelves and wire the surfaces**

`web/src/components/Home.tsx` — pass progress into each row and filter with it. Change the shelf loop in `Home`:

```tsx
      {SHELVES.map((shelf) => (
        <ShelfRow key={shelf.id} genre={shelf.id} title={shelf.title} progress={progress} />
      ))}
```

and the row component's signature and card loop:

```tsx
function ShelfRow({
  genre,
  title,
  progress,
}: {
  genre: string;
  title: string;
  progress: Progress;
}) {
```

```tsx
        <div className="shelf-row">
          {books
            .filter((book) => !progress.isHidden(book.id))
            .map((book) => (
              <BookCard key={book.id} book={book} />
            ))}
        </div>
```

`web/src/App.tsx` — search needs the store now:

```tsx
        <Route path="/search" element={<Search progress={progress} />} />
```

`web/src/components/Search.tsx` — take the prop, keep hidden results visible but marked. Add `import type { Progress } from "../lib/progress";`, change the signature to `export default function Search({ progress }: { progress: Progress })`, and render:

```tsx
          {shown.map((book) => (
            <BookCard
              key={book.id}
              book={book}
              hidden={progress.isHidden(book.id)}
              onToggleHidden={progress.toggleHidden}
            />
          ))}
```

`web/src/components/BookDetail.tsx` — add a toggle directly after the `{saved && (...)}` resume block, still inside the same `<div>`:

```tsx
          <button
            className="hide-toggle"
            onClick={() => progress.toggleHidden(book.id)}
          >
            {progress.isHidden(book.id) ? "Unhide from shelves" : "Hide from shelves"}
          </button>
```

- [ ] **Step 4: Style the new controls** — append to `web/src/styles.css`:

```css
.card-wrap { position: relative; width: 150px; flex-shrink: 0; }
.shelf-grid .card-wrap { width: auto; }
.card-hidden .card img, .card-hidden .card-placeholder { opacity: 0.35; }

.card-hide {
  position: absolute; top: 0.35rem; right: 0.35rem;
  padding: 0.05rem 0.45rem; border-radius: 999px;
  background: rgba(23, 23, 28, 0.85);
  opacity: 0; transition: opacity 0.15s;
}
.card-wrap:hover .card-hide, .card-hide:focus { opacity: 1; }

.card-badge {
  position: absolute; top: 0.35rem; left: 0.35rem;
  font-size: 0.6rem; letter-spacing: 0.05em; text-transform: uppercase;
  color: var(--dim); background: rgba(23, 23, 28, 0.85);
  border-radius: 4px; padding: 0.1rem 0.35rem;
}

.hide-toggle { display: block; margin-top: 0.5rem; font-size: 0.85rem; }
```

- [ ] **Step 5: Verify**

Run: `cd web && npm test && npm run build && npx tsc --noEmit`
Expected: all tests PASS, build succeeds, typecheck clean (this catches any missed `Search`/`ShelfRow` prop wiring).

- [ ] **Step 6: Commit**

```bash
git add web/src/lib/progress.ts web/src/App.tsx web/src/components web/src/styles.css
git commit -m "feat: hide books from web shelves, unhide from search"
```

---

### Task 3: tvOS Core — hidden state in CloudProgress and ProgressStore

**Files:**
- Modify: `AudiobooksTV/Core/CloudProgress.swift`, `AudiobooksTV/Core/ProgressStore.swift`
- Test: `Tests/AudiobooksCoreTests/CloudProgressTests.swift`, `Tests/AudiobooksCoreTests/StoreHookTests.swift`

**Interfaces:**
- Produces:
  - `CloudProgress` gains `hiddenMarks`, `unhiddenMarks`, `static bookKey(bookID: Int) -> String`, `isHidden(bookID: Int) -> Bool`, `localHidden: Set<Int>`, and a `hidden:` parameter on `fromLocal`
  - `ProgressStore` gains `@Published private(set) var hidden: Set<Int>`, `isHidden(bookID:)`, `toggleHidden(bookID:)`, hooks `onHiddenMarked: ((Int) -> Void)?` / `onHiddenUnmarked: ((Int) -> Void)?`, and `applyRemote(items:finished:hidden:)`
- Note: `applyRemote` and `fromLocal` change signature. Their only caller is `CloudProgressMirror` (Task 4) plus the existing tests updated here.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/AudiobooksCoreTests/CloudProgressTests.swift`:

```swift
    func testBookKeyMatchesPositionsKey() {
        XCTAssertEqual(CloudProgress.bookKey(bookID: 52), "52")
    }

    func testIsHiddenMarkTombstoneSemantics() {
        var state = CloudProgress.empty
        XCTAssertFalse(state.isHidden(bookID: 52))
        state.hiddenMarks["52"] = 100
        XCTAssertTrue(state.isHidden(bookID: 52))
        state.unhiddenMarks["52"] = 200
        XCTAssertFalse(state.isHidden(bookID: 52))
        state.hiddenMarks["52"] = 300
        XCTAssertTrue(state.isHidden(bookID: 52))
    }

    func testMergeTakesPerKeyMaximumsOfHiddenMarks() {
        var a = CloudProgress.empty
        a.hiddenMarks = ["1": 100, "52": 300]
        a.unhiddenMarks = ["52": 200]
        var b = CloudProgress.empty
        b.hiddenMarks = ["2": 150, "52": 250]
        b.unhiddenMarks = ["52": 400]
        let merged = CloudProgress.merge(a, b)
        XCTAssertEqual(merged.hiddenMarks, ["1": 100, "2": 150, "52": 300])
        XCTAssertEqual(merged.unhiddenMarks, ["52": 400])
        XCTAssertTrue(merged.isHidden(bookID: 1))
        XCTAssertFalse(merged.isHidden(bookID: 52))
    }

    func testStaleUnhideCannotResurrectNewerHide() {
        var a = CloudProgress.empty
        a.hiddenMarks["52"] = 300
        a.unhiddenMarks["52"] = 200
        var b = CloudProgress.empty
        b.hiddenMarks["52"] = 100
        b.unhiddenMarks["52"] = 200
        XCTAssertTrue(CloudProgress.merge(a, b).isHidden(bookID: 52))
    }

    func testFromLocalUploadsHiddenAtNow() {
        let now = Date(timeIntervalSince1970: 2000)
        let cloud = CloudProgress.fromLocal(items: [], finished: [:], hidden: [52, 7], now: now)
        XCTAssertEqual(cloud.hiddenMarks["52"], 2_000_000)
        XCTAssertEqual(cloud.hiddenMarks["7"], 2_000_000)
        XCTAssertEqual(cloud.localHidden, [7, 52])
    }

    func testLocalHiddenExcludesNewerUnhides() {
        var cloud = CloudProgress.empty
        cloud.hiddenMarks = ["52": 100, "7": 100]
        cloud.unhiddenMarks = ["7": 200]
        XCTAssertEqual(cloud.localHidden, [52])
    }

    func testDictionaryRoundTripCarriesHiddenMaps() {
        var cloud = CloudProgress.empty
        cloud.hiddenMarks["52"] = 100
        cloud.unhiddenMarks["7"] = 200
        XCTAssertEqual(CloudProgress.fromDictionary(cloud.asDictionary), cloud)
    }
```

Add to `Tests/AudiobooksCoreTests/StoreHookTests.swift`:

```swift
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
```

In the same file, update the one existing `applyRemote` call inside `testApplyRemoteDoesNotFireHooksButPersists` to the new signature:

```swift
        store.applyRemote(items: [progress], finished: [9: [1]], hidden: [])
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test`
Expected: FAIL — `bookKey`, `isHidden`, `localHidden`, `hidden:`, and the hook properties don't exist.

- [ ] **Step 3: Implement `CloudProgress`**

In `AudiobooksTV/Core/CloudProgress.swift`, extend the struct's stored properties and `empty`:

```swift
struct CloudProgress: Equatable {
    var positions: [String: CloudPosition]
    var finishedMarks: [String: Double]
    var unfinishedMarks: [String: Double]
    var hiddenMarks: [String: Double]
    var unhiddenMarks: [String: Double]

    static let empty = CloudProgress(
        positions: [:], finishedMarks: [:], unfinishedMarks: [:],
        hiddenMarks: [:], unhiddenMarks: [:]
    )
```

Add the key helper next to `sectionKey`, and the predicate next to `isFinished`:

```swift
    /// Key for the per-book hidden maps; matches the `positions` map's keys.
    static func bookKey(bookID: Int) -> String {
        String(bookID)
    }
```

```swift
    /// Hidden iff the hide mark is newer than any unhide mark — the same
    /// rule as finished sections, keyed by book instead of section.
    func isHidden(bookID: Int) -> Bool {
        let key = Self.bookKey(bookID: bookID)
        guard let hidden = hiddenMarks[key] else { return false }
        guard let unhidden = unhiddenMarks[key] else { return true }
        return hidden > unhidden
    }
```

Carry both maps through `merge`:

```swift
        return CloudProgress(
            positions: positions,
            finishedMarks: a.finishedMarks.merging(b.finishedMarks, uniquingKeysWith: max),
            unfinishedMarks: a.unfinishedMarks.merging(b.unfinishedMarks, uniquingKeysWith: max),
            hiddenMarks: a.hiddenMarks.merging(b.hiddenMarks, uniquingKeysWith: max),
            unhiddenMarks: a.unhiddenMarks.merging(b.unhiddenMarks, uniquingKeysWith: max)
        )
```

Extend `fromLocal` with the hidden set (hidden books, like finished sections, have no local timestamp and upload at `now`):

```swift
    static func fromLocal(
        items: [PlaybackProgress], finished: [Int: Set<Int>], hidden: Set<Int>,
        now: Date = Date()
    ) -> CloudProgress {
```

and replace its `return` with:

```swift
        var hiddenMarks: [String: Double] = [:]
        for bookID in hidden {
            hiddenMarks[bookKey(bookID: bookID)] = ms
        }
        return CloudProgress(
            positions: positions, finishedMarks: marks, unfinishedMarks: [:],
            hiddenMarks: hiddenMarks, unhiddenMarks: [:]
        )
```

Add the local projection next to `localFinished`:

```swift
    /// Effective hidden books (marks minus newer tombstones).
    var localHidden: Set<Int> {
        var result: Set<Int> = []
        for key in hiddenMarks.keys {
            guard let bookID = Int(key), isHidden(bookID: bookID) else { continue }
            result.insert(bookID)
        }
        return result
    }
```

Extend both dictionary converters — in `fromDictionary`, after the existing two mark lines:

```swift
        progress.hiddenMarks = Self.numberMap(dict["hiddenMarks"])
        progress.unhiddenMarks = Self.numberMap(dict["unhiddenMarks"])
```

and in `asDictionary`'s returned literal:

```swift
        return [
            "positions": rawPositions,
            "finishedMarks": finishedMarks,
            "unfinishedMarks": unfinishedMarks,
            "hiddenMarks": hiddenMarks,
            "unhiddenMarks": unhiddenMarks,
        ]
```

- [ ] **Step 4: Implement `ProgressStore`**

In `AudiobooksTV/Core/ProgressStore.swift`, add the storage key beside the existing ones:

```swift
    private static let hiddenKey = "hiddenBooks.v1"
```

the published set beside `finished`:

```swift
    /// Book IDs hidden from the Home shelves. Search still shows them.
    @Published private(set) var hidden: Set<Int> = []
```

the hooks beside the finished ones:

```swift
    var onHiddenMarked: ((Int) -> Void)?
    var onHiddenUnmarked: ((Int) -> Void)?
```

load it in `init`, after the `finished` decode:

```swift
        if let data = defaults.data(forKey: Self.hiddenKey),
           let decoded = try? JSONDecoder().decode(Set<Int>.self, from: data) {
            hidden = decoded
        }
```

the accessors, after `toggleFinished`:

```swift
    func isHidden(bookID: Int) -> Bool {
        hidden.contains(bookID)
    }

    func toggleHidden(bookID: Int) {
        if hidden.contains(bookID) {
            hidden.remove(bookID)
            persistHidden()
            onHiddenUnmarked?(bookID)
        } else {
            hidden.insert(bookID)
            persistHidden()
            onHiddenMarked?(bookID)
        }
    }
```

the widened remote application:

```swift
    func applyRemote(items: [PlaybackProgress], finished: [Int: Set<Int>], hidden: Set<Int>) {
        self.items = items
        self.finished = finished
        self.hidden = hidden
        persist()
        persistFinished()
        persistHidden()
    }
```

and the persistence helper beside the others:

```swift
    private func persistHidden() {
        if let data = try? JSONEncoder().encode(hidden) {
            defaults.set(data, forKey: Self.hiddenKey)
        }
    }
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test`
Expected: all suites PASS, including the 9 new cases.

- [ ] **Step 6: Commit**

```bash
git add AudiobooksTV/Core/CloudProgress.swift AudiobooksTV/Core/ProgressStore.swift Tests/AudiobooksCoreTests
git commit -m "feat: hidden-book state in tvOS Core with merge parity"
```

---

### Task 4: tvOS — mirror wiring and hide controls

**Files:**
- Modify: `AudiobooksTV/Services/CloudProgressMirror.swift`, `AudiobooksTV/Views/ShelfRowView.swift`, `AudiobooksTV/Views/BookCardView.swift`, `AudiobooksTV/Views/SearchView.swift`, `AudiobooksTV/Views/BookDetailView.swift`

**Interfaces:**
- Consumes: everything Task 3 produced (`CloudProgress.bookKey`, `isHidden`, `localHidden`, `fromLocal(items:finished:hidden:now:)`, `ProgressStore.hidden`, `isHidden(bookID:)`, `toggleHidden(bookID:)`, the two hooks, `applyRemote(items:finished:hidden:)`).
- Produces: `BookCardView` gains `var isHidden: Bool = false`.

- [ ] **Step 1: Wire the mirror** — `AudiobooksTV/Services/CloudProgressMirror.swift`

Replace `writeMark` entirely. The old version branched on a string literal to decide which local map to update, which a fourth and fifth map would make actively dangerous:

```swift
    /// Writes one mark-map entry and mirrors it into `lastKnown`. The key
    /// path and the Firestore field name travel together, so the local
    /// mirror can't drift from what gets written remotely.
    private func writeMark(
        _ field: WritableKeyPath<CloudProgress, [String: Double]>,
        named name: String,
        key: String
    ) {
        let now = Date().timeIntervalSince1970 * 1000
        lastKnown[keyPath: field][key] = now
        progressDoc?.setData([name: [key: now]], merge: true)
    }
```

Update the two existing hook registrations and add the two new ones, in `attach()`:

```swift
        store.onFinishedMarked = { [weak self] bookID, sectionIndex in
            self?.writeMark(
                \.finishedMarks, named: "finishedMarks",
                key: CloudProgress.sectionKey(bookID: bookID, sectionIndex: sectionIndex)
            )
        }
        store.onFinishedUnmarked = { [weak self] bookID, sectionIndex in
            self?.writeMark(
                \.unfinishedMarks, named: "unfinishedMarks",
                key: CloudProgress.sectionKey(bookID: bookID, sectionIndex: sectionIndex)
            )
        }
        store.onHiddenMarked = { [weak self] bookID in
            self?.writeMark(
                \.hiddenMarks, named: "hiddenMarks",
                key: CloudProgress.bookKey(bookID: bookID)
            )
        }
        store.onHiddenUnmarked = { [weak self] bookID in
            self?.writeMark(
                \.unhiddenMarks, named: "unhiddenMarks",
                key: CloudProgress.bookKey(bookID: bookID)
            )
        }
```

Include hidden books in the first-sign-in upload:

```swift
        let localCloud = CloudProgress.fromLocal(
            items: store.items, finished: store.finished, hidden: store.hidden
        )
```

and in the snapshot application:

```swift
                ProgressStore.shared.applyRemote(
                    items: merged.localItems,
                    finished: merged.localFinished,
                    hidden: merged.localHidden
                )
```

Clear the new hooks in `detach()`, beside the existing ones:

```swift
        ProgressStore.shared.onHiddenMarked = nil
        ProgressStore.shared.onHiddenUnmarked = nil
```

- [ ] **Step 2: Filter shelves and add the long-press menu** — `AudiobooksTV/Views/ShelfRowView.swift`

Add the store observation beside the existing `@State` properties:

```swift
    @ObservedObject private var progressStore = ProgressStore.shared
```

Replace `visibleBooks`:

```swift
    private var visibleBooks: [Audiobook] {
        books.filter { book in
            !progressStore.isHidden(bookID: book.id) && (!readAlongOnly || book.hasText)
        }
    }
```

Attach a context menu to each card (long-press Select on the Siri Remote):

```swift
                    ForEach(visibleBooks) { book in
                        NavigationLink(value: book) {
                            BookCardView(book: book)
                        }
                        .buttonStyle(.card)
                        .contextMenu {
                            Button {
                                progressStore.toggleHidden(bookID: book.id)
                            } label: {
                                Label("Hide", systemImage: "eye.slash")
                            }
                        }
                    }
```

- [ ] **Step 3: Mark hidden cards** — `AudiobooksTV/Views/BookCardView.swift`

Add the parameter beside `book`:

```swift
struct BookCardView: View {
    let book: Audiobook
    /// Only set in search results; shelves filter hidden books out entirely.
    var isHidden: Bool = false
```

and dim the cover with a badge by replacing the `.frame(width: 280, height: 280)` modifier chain on the `AsyncImage` with:

```swift
            .frame(width: 280, height: 280)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isHidden ? 0.4 : 1)
            .overlay(alignment: .topTrailing) {
                if isHidden {
                    Image(systemName: "eye.slash.fill")
                        .font(.caption)
                        .padding(8)
                        .background(.black.opacity(0.6), in: Circle())
                        .padding(8)
                }
            }
```

- [ ] **Step 4: Let search unhide** — `AudiobooksTV/Views/SearchView.swift`

Add the store observation beside the existing `@AppStorage` and `@State` properties:

```swift
    @ObservedObject private var progressStore = ProgressStore.shared
```

and replace the results loop so hidden books stay listed, marked, with the menu offering the inverse action:

```swift
                    ForEach(visibleResults) { book in
                        NavigationLink(value: book) {
                            BookCardView(book: book, isHidden: progressStore.isHidden(bookID: book.id))
                        }
                        .buttonStyle(.card)
                        .contextMenu {
                            Button {
                                progressStore.toggleHidden(bookID: book.id)
                            } label: {
                                let hidden = progressStore.isHidden(bookID: book.id)
                                Label(hidden ? "Unhide" : "Hide",
                                      systemImage: hidden ? "eye" : "eye.slash")
                            }
                        }
                    }
```

- [ ] **Step 5: Add the detail-page button** — `AudiobooksTV/Views/BookDetailView.swift`

Insert directly after the existing Play/Resume `Button` (which ends with `.disabled(book.sections.isEmpty)`):

```swift
                    Button {
                        progressStore.toggleHidden(bookID: book.id)
                    } label: {
                        let hidden = progressStore.isHidden(bookID: book.id)
                        Label(hidden ? "Unhide from Shelves" : "Hide from Shelves",
                              systemImage: hidden ? "eye" : "eye.slash")
                    }
```

(The view already holds `@ObservedObject private var progressStore = ProgressStore.shared`.)

- [ ] **Step 6: Verify**

Run: `swift test`
Expected: all suites PASS (Core is untouched by this task, so this is a regression check).

Run: `xcodebuild -project AudiobooksTV.xcodeproj -scheme AudiobooksTV -destination 'platform=tvOS Simulator,name=Apple TV' build CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED with no warnings.

- [ ] **Step 7: Commit**

```bash
git add AudiobooksTV/Services/CloudProgressMirror.swift AudiobooksTV/Views
git commit -m "feat: hide books from tvOS shelves, unhide from search"
```

---

## Verification

After all tasks:

1. `cd web && npm test && npm run build && npx tsc --noEmit` — green.
2. `swift test` — green, including the new CloudProgress and ProgressStore cases.
3. tvOS simulator build succeeds.
4. Cross-device, signed into the same account: hide a book on the web and it disappears from that shelf on tvOS (and vice versa); the book still appears in search on both, marked; unhiding from search restores it to the shelf on both.
5. Hiding a book that has saved progress leaves it in Continue Listening on both platforms.
