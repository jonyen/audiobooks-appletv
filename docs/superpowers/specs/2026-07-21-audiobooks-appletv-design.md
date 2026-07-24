# AudiobooksTV — Read-Along Audiobooks for Apple TV

**Date:** 2026-07-21
**Status:** Approved — superseded in part

> **Note (2026-07-24):** two items listed under "Out of scope (v1)" below —
> user accounts and sync across devices — have since shipped. See
> `2026-07-23-web-port-synced-progress-design.md` for the current auth and
> sync design, including its 2026-07-24 amendment swapping Apple sign-in
> for Google.

## Premise

A SwiftUI tvOS app, derived from BibleTV (jonyen/bible-appletv), that plays free
public-domain audiobooks from LibriVox while displaying the matching book text
from Project Gutenberg on screen. The read-along experience — text on screen,
audio narrating, auto-advance chapter by chapter — is the core feature, not an
add-on.

## Content sources

- **Audio:** LibriVox (librivox.org). ~45,000 public-domain audiobooks. Open
  JSON API, no key. MP3 files hosted on archive.org.
- **Text:** Project Gutenberg. LibriVox book records carry a
  `url_text_source` field that usually points at gutenberg.org — this is the
  bridge between audio and text.
- **Cover art:** archive.org item thumbnails, with fallback chain (LibriVox
  API field → archive.org `__ia_thumb.jpg` → placeholder).

All content is public domain; no licensing constraints (unlike the ESV API in
BibleTV). No API keys anywhere — `Secrets.swift` and `SetupView` are removed.

## Architecture

Same three-layer shape as BibleTV: Models / Services / Views. Xcode target
renamed `AudiobooksTV`, new bundle id, repo `jonyen/audiobooks-appletv`
(private, history carried over from bible-appletv).

### Models

- `Audiobook`: id, title, authors, description, genres, coverURL,
  urlTextSource, sections. `hasText` computed: urlTextSource points at
  gutenberg.org.
- `Section`: id, title, mp3 URL, duration, sectionNumber.
- `Shelf`: display title + LibriVox genre query. Hardcoded list: Fiction,
  Mystery, Science Fiction, Children's, History, Adventure, Poetry.

### Services

- `LibriVoxClient` (replaces `ESVClient`):
  - Shelf fetch: `/api/feed/audiobooks?genre=<g>&format=json&extended=1`
  - Search by title and author
  - Section list with direct MP3 URLs
  - In-memory cache of shelf responses per session (API can be slow)
- `GutenbergClient` (new): extract Gutenberg ID from `url_text_source`, fetch
  plain text from `gutenberg.org/cache/epub/{id}/pg{id}.txt`, strip Project
  Gutenberg boilerplate header/footer, cache full text on disk.
- `ChapterSplitter` (new): split plain text into chapters by heading patterns
  (CHAPTER I / Chapter 1 / bare Roman numerals / BOOK + CHAPTER / LETTER /
  STAVE, etc.).
- `SectionAligner` (new): map each LibriVox audio section to a text chapter.
  Title normalization (Roman→Arabic numerals, strip punctuation/quotes), exact
  match first, fuzzy fallback, positional fallback (section N ↔ chapter N when
  counts are equal). Computed once per book, cached.
- `AudioPlayerModel`: reused from BibleTV as-is (play/pause, 0.75×–1.5× speed,
  progress, finish events, auto-advance).
- `ProgressStore` (new): persist last position per book in UserDefaults
  (bookID, sectionIndex, seconds). Feeds a "Continue Listening" shelf.
- Audio disk cache for recent sections: carried over from BibleTV.

### Views

- `HomeView`: "Continue Listening" row (from ProgressStore) + genre shelves as
  horizontal card rows. Filter toggle: **Read-along only**.
- `SearchView`: tvOS search, results grid, same filter toggle.
- `BookDetailView`: cover, description, author, chapter list, Play/Resume.
  After text load, shows "Read-along: N of M chapters matched".
- `PlayerView` (read-along; evolved from BibleTV `ReaderView`): chapter text in
  large serif, scrollable with the remote, audio controls (play/pause, speed,
  progress). Auto-advance flips text and audio to the next chapter together.

### Text-availability UX

- Browse cards tint the title: normal color = text available, dimmed/gray =
  audio-only. Signal is `hasText` (cheap, from the shelf/search response — no
  extra fetch).
- The indicator only promises text *exists*; per-chapter alignment is verified
  when the book is opened.

### Failure handling

- Per-view async load states (loading / error / loaded) with retry, same
  pattern as BibleTV.
- Section alignment fails for a chapter → whole-book text scroll for that
  chapter.
- No text at all (fetch fails or no Gutenberg source) → cover-only player with
  a "text unavailable" notice.

## Testing

Build and run in the tvOS simulator. Smoke tests:

1. Home loads shelves with covers; text-availability tinting visible.
2. Read-along filter hides audio-only books.
3. Search returns results.
4. Open a classic (e.g. Pride and Prejudice): chapters align, text displays,
   audio plays, speed control works.
5. Auto-advance moves text + audio to next chapter.
6. Relaunch app: Continue Listening resumes at saved position.
7. Book without Gutenberg source: cover-only player, notice shown.

## Out of scope (v1)

- Word- or sentence-level text/audio sync (no timing data exists).
- Downloads for offline listening beyond the recent-sections cache.
- User accounts, sync across devices.
- Non-Gutenberg text sources.
