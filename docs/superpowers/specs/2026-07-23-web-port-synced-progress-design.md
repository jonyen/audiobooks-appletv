# Web Port with Synced Listening Progress — Design

**Date:** 2026-07-23
**Status:** Draft for review

## Goal

Port the AudiobooksTV Apple TV app to a web app with feature parity (browse
genre shelves, search, read-along player with paragraph-synced text follow,
speed control, auto-advance, preamble auto-skip, Continue Listening), and sync
listening progress two-way between the tvOS app and the web app. Users sign in
with their Apple account. All backend services run on free tiers. This mirrors
the bible-appletv web port's architecture.

## Architecture

Three pieces:

1. **Web app** — React + Vite + TypeScript single-page app, deployed as
   static files to Cloudflare Pages. No server rendering; everything is
   behind sign-in.
2. **Catalog/text proxy** — Cloudflare Pages Functions under `/api/*` on the
   same deployment. Needed only because two upstreams send no CORS headers
   (verified 2026-07-23):
   - `GET /api/librivox?...` → LibriVox catalog API (browse, search, book
     detail), query passthrough
   - `GET /api/gutenberg/:ebookID` → Project Gutenberg plain-text download
   - Audio is **not** proxied: archive.org serves LibriVox MP3s with
     `Access-Control-Allow-Origin: *` and Range support, so streaming and
     Web Audio analysis hit it directly.
   - There is no API key to protect, so the proxy takes no auth token.
     Instead: a fixed upstream allowlist (exactly those two hosts and path
     shapes) and aggressive edge caching via the Cache API (public-domain,
     effectively immutable content; long TTLs) to keep load off LibriVox and
     Gutenberg and make abuse pointless.
3. **Firebase (own project, Spark free tier)** — Auth with the **Apple**
   provider for sign-in, Firestore for synced state. Separate from the
   bible-appletv Firebase project: own data, rules, and quotas. Requires the
   same one-time Apple Developer portal setup (Services ID, web domain
   verification, Sign in with Apple key configured in the Firebase console).

## Authentication

- **Web:** Firebase Auth `OAuthProvider("apple.com")` popup/redirect flow.
  Sign-in is **required** on the web app (its purpose is synced listening).
- **tvOS:** native Sign in with Apple via `AuthenticationServices`, identity
  token exchanged for a Firebase credential. Sign-in is **optional**: signed
  out, the app behaves exactly as today with local `UserDefaults` state.

## Data model & sync

Two Firestore documents per user.

`users/{uid}/state/progress`:

```
positions:       { "<bookID>": { bookTitle, coverURL, sectionIndex,
                                 seconds, updatedAt } }
finishedMarks:   { "<bookID>#<sectionIndex>": <ms epoch> }
unfinishedMarks: { "<bookID>#<sectionIndex>": <ms epoch> }
```

- **`positions`** is last-writer-wins per book by `updatedAt` — the cloud
  form of `PlaybackProgress`. Continue Listening renders the newest 20 by
  `updatedAt`; the map itself is not capped by the merge (merging never
  drops the other device's newer entry).
- **Finished sections** use the mark/tombstone pattern proven in
  bible-appletv: marking finished sets `finishedMarks[key] = now`; unmarking
  sets `unfinishedMarks[key] = now`; neither deletes the other's entry. A
  section is finished iff its `finishedMarks` entry is newer than any
  `unfinishedMarks` entry for the same key. Merging takes the per-key
  maximum of each map, so a stale device can never resurrect an explicitly
  unmarked section, and re-marking after an unmark survives merges. This
  implements `toggleFinished` semantics across devices.

`users/{uid}/state/preambles`:

```
offsets: { "<sectionID>": <seconds> }    // 0 = analyzed, nothing to skip
```

Preamble offsets are objective facts about the audio, not user preferences,
so the merge is trivial: any present value wins over absence; concurrent
writes for the same key are equivalent. Syncing them means whichever device
analyzes a section first spares the other the work.

Sync mechanics (both platforms):

- Snapshot listeners apply remote changes live using the merge rules above.
- Firestore security rules restrict each user to `users/{uid}/**`.
- Firestore offline persistence queues writes made while offline.
- **First sign-in on tvOS:** local `UserDefaults` state uploads and unions
  into the cloud docs, then every subsequent change mirrors to both.

## Web app structure

```
web/
├── src/
│   ├── lib/                     // TS ports of Core/ — same algorithms,
│   │   │                        // same fixtures as the Swift tests
│   │   ├── librivox.ts          // LibriVoxParser port (JSON → models)
│   │   ├── gutenberg.ts         // ebook ID extraction, boilerplate strip
│   │   ├── chapterSplitter.ts   // plain text → chapters
│   │   ├── sectionAligner.ts    // audio sections ↔ text chapters
│   │   ├── romanNumerals.ts
│   │   ├── paragraphTimeline.ts // estimates + leadIn (ParagraphTimeline)
│   │   ├── preambleDetector.ts  // silence-gap algorithm (PreambleDetector)
│   │   ├── audioAnalyzer.ts     // Web Audio: Range-fetch leading MP3
│   │   │                        // bytes, decodeAudioData, RMS windows
│   │   ├── shelves.ts           // genre shelf definitions (Shelf)
│   │   ├── progress.ts          // Firestore-backed store + merge rules
│   │   └── firebase.ts          // app init, auth helpers
│   ├── components/
│   │   ├── SignIn.tsx           // Apple sign-in screen
│   │   ├── Home.tsx             // genre shelves + Continue Listening
│   │   ├── Search.tsx           // title/author search, read-along filter
│   │   ├── BookDetail.tsx       // info, section list (gold = finished),
│   │   │                        // match summary
│   │   ├── Player.tsx           // read-along: text, paragraph follow
│   │   └── AudioControls.tsx    // play/pause, 0.75×–1.5×, seek,
│   │                            // auto-advance
│   └── App.tsx                  // routing + auth gate
└── functions/api/               // Pages Functions: librivox + gutenberg
                                 // proxies, upstream allowlist, edge cache
```

## Player behavior

Mirrors tvOS:

- `<audio>` streams directly from archive.org. `timeupdate` events drive the
  estimated current paragraph via `paragraphTimeline` (with `leadIn` from
  the preamble offset) and smooth-scroll it into view. Manual scrolling
  suspends auto-follow until the section changes or the user resumes.
- On a fresh section start with no cached offset, `audioAnalyzer`
  Range-fetches the leading ~90 seconds of the MP3, decodes it with the Web
  Audio API, and `preambleDetector` runs the same silence-gap algorithm as
  the Swift implementation — including its refinements: defer the skip seek
  until duration is known, never cache an offset on cancellation, never
  treat array-end silence as a preamble, and apply `leadIn` on resume.
  Detected offsets write to the synced `preambles` doc.
- Audio `ended` marks the section finished and auto-advances to the next
  section (updating position), matching tvOS auto-advance.
- Speed control 0.75×–1.5× via `playbackRate`.

## tvOS changes

Kept minimal:

- Add Firebase Auth + Firestore SDKs via Swift Package Manager.
- A small account view (library header or settings): Sign in with Apple
  button, signed-in state, sign out.
- `ProgressStore` and `PreambleOffsetStore` gain cloud mirrors behind their
  existing public APIs: writes always go to `UserDefaults`, additionally to
  Firestore when signed in; snapshot listeners apply remote changes using
  the merge rules.
- No behavior change when signed out.

## Error handling

- **Web:** auth gate on all routes; catalog/text fetch failures show retry
  states; books whose text fails or doesn't match fall back to audio-only
  display (as tvOS does); preamble analysis failure means no skip —
  estimates run without `leadIn`; Firestore errors never block local writes.
- **Proxy:** upstream errors pass through with status; requests outside the
  allowlist get 404; cache errors fall through to a live fetch.
- **tvOS:** Firestore errors never block `UserDefaults` writes; retries are
  left to Firestore's SDK.

## Testing

- **Web:** Vitest unit tests for every `lib/` port, reusing the Swift test
  fixtures verbatim so both implementations stay in agreement; merge-rule
  tests (LWW positions, mark/tombstone finished sections, preamble union).
- **Proxy:** allowlist and passthrough tests via `wrangler dev`/Miniflare.
- **tvOS:** extend the Swift tests with the same merge-rule cases (union,
  unmark tombstones, first-sign-in upload).

## Out of scope

- Offline listening on the web beyond Firestore's write queue
- Any account system other than Apple
- On-device MP3 caching in the browser (the tvOS app's download cache has
  no web equivalent here; streaming only)
- Restructuring the tvOS app beyond the store mirrors and sign-in
