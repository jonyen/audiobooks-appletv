# Read-Along Sync: Port of BibleTV Reader Features

Date: 2026-07-21
Status: Approved

## Goal

Port the 2026-07-20 bible-appletv reader features into the AudiobooksTV
read-along player, adapted from verse/chapter concepts to paragraph/section
concepts:

1. Highlight the narrated paragraph and dim the rest during playback.
2. Auto-scroll the narrated paragraph to the top of the frame; a manual
   focus move suspends following for 10 seconds.
3. Collapse the player controls entirely during playback; reveal with an
   up-press at the top of the text; re-collapse when focus settles back
   into the text.
4. Mark finished sections and render their titles in gold in the book
   detail section list.

Not ported: exact ESV verse timings (LibriVox has no per-segment audio
clips) and lead-in removal (LibriVox spoken preambles are baked into the
audio). Paragraph-level estimation absorbs the resulting drift.

## Components

### ParagraphTimeline (new, `AudiobooksTV/Core/ParagraphTimeline.swift`)

Port of BibleTV's `VerseTimeline` estimator, at paragraph granularity.

- `static func paragraphs(from body: String) -> [String]` — split chapter
  body into paragraphs on blank lines (runs of `\n\s*\n`), trimming
  whitespace, dropping empties.
- `init?(paragraphs: [String], duration: Double)` — nil when paragraphs
  is empty or duration <= 0. Start time of paragraph *i* is proportional
  to the cumulative character count of paragraphs 0..<i over the total.
- `func paragraphIndex(at seconds: Double) -> Int?` — the paragraph being
  narrated at a playback position; clamps below 0 to the first and beyond
  duration to the last paragraph.

Lives in the SPM `AudiobooksCore` target with unit tests.

### PlayerView read-along sync

- Render the chapter as one `Text` per paragraph (focusable), not one
  monolithic `Text`.
- Rebuild the timeline when `audio.duration` changes or the section/chapter
  changes; track `currentParagraphIndex` from `audio.currentTime`.
- While `audio.isPlaying`, dim all paragraphs to `.secondary` except the
  narrated one (`.primary`); when paused, all render `.primary`.
- Auto-scroll with `ScrollPosition`, targeting the narrated paragraph's
  frame top (collected via a `PreferenceKey` of paragraph frames in a
  named coordinate space), animated ease-in-out 0.6s.
  **Deviation:** the app targets tvOS 17, so the implementation uses
  `.scrollPosition(id:anchor: .top)` with `.scrollTargetLayout()` instead,
  scrolling to the narrated paragraph's `.id(index)` with no frame tracking.
- A user-driven focus change between paragraphs during playback sets
  `followSuspendedUntil = now + 10s`; programmatic focus handoff at play
  start is exempt (`suppressFocusSuspension` flag); focus dropping to nil
  (auto-scroll pushing the focused row off-screen) is exempt. Suspension
  resets on section change.
- Highlighting/scrolling only applies when a single aligned chapter is
  shown. The whole-book fallback and cover-only paths keep current
  behavior.

### Auto-hiding controls

- `controlsVisible = !audio.isPlaying || controlsRevealed`.
- The control bar and progress bar collapse out of the layout entirely
  when hidden (same `if` + `animation(.easeInOut(duration: 0.25))`
  approach as BibleTV).
- `.onMoveCommand(.up)` — which fires only when the focus engine has no
  target above, i.e. at the top of the text with controls collapsed —
  sets `controlsRevealed = true`.
- Focus settling back into a paragraph sets `controlsRevealed = false`.
- `.onPlayPauseCommand` toggles play/pause so the Siri Remote works with
  controls hidden.

### Finished sections (ProgressStore + BookDetailView)

- `ProgressStore` gains `finishedSections(bookID:) -> Set<Int>`,
  `markFinished(bookID:sectionIndex:)`, and
  `toggleFinished(bookID:sectionIndex:)`, persisted alongside existing
  progress data and covered by unit tests.
- PlayerView marks the current section finished when its audio completes
  (in the section-finished callback, before auto-advance), and offers a
  manual toggle button in the control bar (checkmark icon, mirroring
  BibleTV's).
- `BookDetailView`'s section list renders finished sections' titles in
  gold (`Color(red: 0.85, green: 0.65, blue: 0.13)`-style, matching
  BibleTV's read-chapter gold) instead of adding a checkmark.

## Error handling

- Timeline construction failure (no text, zero duration) simply disables
  highlighting/auto-scroll; playback is unaffected.
- All new state resets on section change (timeline, current paragraph,
  frames, suspension), as BibleTV does on chapter change.

## Testing

- Unit tests (SPM): paragraph splitting (blank-line runs, CRLF, trailing
  whitespace), timeline estimation (proportionality, boundaries, clamps,
  nil cases), ProgressStore finished-section persistence and toggling.
- UI behavior (controls hiding, scroll-following) verified manually in
  the tvOS simulator.
