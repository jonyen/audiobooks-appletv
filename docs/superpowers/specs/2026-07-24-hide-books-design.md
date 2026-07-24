# Hiding Books — Design

**Date:** 2026-07-24
**Status:** Approved

## Goal

Let a user hide books they'll never want, so the Home shelves stop showing
them. Hiding syncs between the tvOS app and the web app like every other
piece of user state. Search deliberately keeps showing hidden books —
marked as hidden — so searching still works as an explicit act and doubles
as the place to unhide.

## Data model & sync

Hiding reuses the mark/tombstone pattern already proven for finished
sections. Two new fields on the existing `users/{uid}/state/progress`
document (no new document, no new snapshot listener):

```
hiddenMarks:   { "<bookID>": <ms epoch> }
unhiddenMarks: { "<bookID>": <ms epoch> }
```

Keys are the book ID alone (`"52"`), matching the `positions` map — hiding
is per book, not per section.

A book is **hidden** iff its `hiddenMarks` entry is newer than any
`unhiddenMarks` entry for the same key. Hiding sets `hiddenMarks[id] = now`;
unhiding sets `unhiddenMarks[id] = now`; neither deletes the other. Merging
takes the per-key maximum of each map — the same `maxByKey` (TypeScript) and
`merging(uniquingKeysWith: max)` (Swift) already used for finished sections,
so a stale device cannot resurrect an explicit unhide, and re-hiding after an
unhide survives merges.

Writes are field-level `setDoc`/`setData` merges on a single top-level field,
so concurrent devices never clobber each other's maps.

### Known limitation

The first-sign-in union upload (tvOS `CloudProgressMirror.attach()`, web's
equivalent) fixes the empty-map-erases-cloud-data bug by dropping empty
top-level maps from the merge write, but it does not fix a smaller residual
issue: local hidden state has no per-book timestamps, so that upload
re-stamps every locally hidden book's `hiddenMarks` entry at `now`. If a book
was unhidden remotely (from another device) while this device was signed
out, its local `hiddenMarks` entry is still present and stale, and the
re-stamped upload can beat the remote `unhiddenMarks` entry, silently
re-hiding the book everywhere. The complete fix is to defer the union upload
until the first snapshot has merged into `lastKnown`, and then upload only
the keys the cloud doc doesn't already carry. The same limitation already
applies to finished-section marks, for the same reason.

## Behavior

- **Home shelves** hide the books, filtered client-side after the LibriVox
  fetch. A shelf fetches 20 books per genre, so hiding 5 leaves a row of 15;
  the app does **not** page the API to backfill.
- **Search** still returns hidden books, rendered dimmed with a slashed-eye
  badge, and offers Unhide in place of Hide. This is the unhide path — there
  is no separate "hidden books" management screen.
- **Continue Listening is unaffected.** Hiding curates the catalog rows; it
  never touches playback positions or finished marks, so a book you're
  part-way through keeps appearing there even while hidden.
- Hiding is reversible at any time and destroys no data.

## tvOS changes

- **`ProgressStore`** gains `@Published private(set) var hidden: Set<Int>`,
  persisted to `UserDefaults` under `hiddenBooks.v1`, with:
  - `isHidden(bookID:) -> Bool`
  - `toggleHidden(bookID:)`
  - cloud hooks `onHiddenMarked` / `onHiddenUnmarked`, matching the existing
    finished-section hooks (fired for user actions only, never for
    `applyRemote`)
  - `applyRemote(items:finished:hidden:)` — the existing signature gains the
    hidden set; it still fires no hooks.
- **`CloudProgress`** (Core, pure Swift) gains `hiddenMarks` /
  `unhiddenMarks`, `isHidden(bookID:)`, `localHidden`, merge coverage, the
  `fromLocal(items:finished:hidden:now:)` parameter, and dictionary
  round-tripping — mirroring what already exists for finished sections.
- **`CloudProgressMirror`** wires the two new hooks and includes hidden state
  in the first-sign-in union upload and in snapshot application.
  - *Targeted cleanup, in scope because this change would otherwise make it
    worse:* `writeMark(field: String, ...)` currently branches on a string
    literal (`if field == "finishedMarks"`) to update `lastKnown`. Adding two
    more mark maps turns that into a four-way string branch. Replace the
    parameter with a `WritableKeyPath<CloudProgress, [String: Double]>` plus
    the Firestore field name, so the local mirror and the remote write can't
    drift apart.
- **`ShelfRowView`** filters hidden books out of `visibleBooks`, alongside the
  existing read-along filter.
- **`BookCardView`** gains an `isHidden: Bool = false` parameter that dims the
  cover and overlays an `eye.slash` badge. Shelves never pass it (hidden books
  aren't shown there); search does.
- **Shelf and search cards** gain a `.contextMenu` (long-press Select on the
  Siri Remote) with a single Hide / Unhide button.
- **`BookDetailView`** gains a Hide / Unhide button beside Play/Resume.

## Web changes

- **`progressMerge.ts`**: `ProgressState` gains `hiddenMarks` and
  `unhiddenMarks`; `emptyProgress()` seeds both; `mergeProgress` passes them
  through the existing `maxByKey`; new `isHidden(state, bookID)` predicate
  mirroring `isFinished`.
- **`progress.ts`**: the `Progress` interface gains `isHidden(bookID)` and
  `toggleHidden(bookID)`, writing field-level merges exactly like
  `toggleFinished`; the snapshot handler reads the two new maps.
- **`Home.tsx`** filters hidden books out of each shelf row.
- **`BookCard.tsx`** gains optional `hidden` and `onToggleHidden` props: a ✕
  control appears on hover/focus and calls the handler; when `hidden` is set
  the card dims and shows a "Hidden" badge.
- **`Search.tsx`** keeps hidden results in the list, passing `hidden` so they
  render marked, with the control offering unhide.
- **`BookDetail.tsx`** gains a Hide / Unhide button next to the resume link.

## Error handling

Hiding follows the established rule: local state updates immediately and
Firestore errors never block it. A failed write is retried by the Firestore
SDK; nothing in the UI waits on the round trip. Applying a remote snapshot
never fires the local hooks, so a synced change cannot echo back as a new
write.

## Testing

- **Web (Vitest):** merge-rule tests for the new maps — hide alone hides;
  a newer unhide wins; a newer re-hide wins back; merging takes per-key
  maxima; a stale unhide cannot resurrect a newer hide. These mirror the
  existing finished-section tests.
- **tvOS (`swift test`):** the same merge cases against `CloudProgress`,
  plus `ProgressStore` hook tests — `toggleHidden` fires the right hook per
  branch, `applyRemote` fires none and persists, and hidden state survives a
  store reload.
- No UI tests on either platform, consistent with the rest of the project.

## Out of scope

- A dedicated "hidden books" management screen (search covers unhiding).
- Backfilling shelf rows to replace hidden books.
- Hiding individual sections, authors, or whole genres.
- Any change to Continue Listening, progress, or finished-section behavior.
