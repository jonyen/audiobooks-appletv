# Preamble Skip: Auto-Skip LibriVox Spoken Credits

Date: 2026-07-21
Status: Approved

## Goal

Every LibriVox section opens with spoken credits ("This is a LibriVox
recording…", reader name, book/chapter announcement) of varying length,
typically 10–30 seconds. When a section starts from the beginning,
automatically jump past the credits to the start of narration, and feed
the detected offset into the read-along timeline so paragraph highlighting
no longer drifts by the preamble length.

No skip on resume (saved position > 0). No UI; the behavior is automatic
and silent. If detection fails or finds nothing, playback is unchanged.

## Detection heuristic

Decode only the first 60 seconds of the cached audio file into RMS
loudness windows of 50 ms. A window is silent when its RMS falls below
20% of the clip's median RMS (computed over non-zero windows). A silence
run qualifies when it lasts >= 0.8 s and its end lies in [8 s, 60 s].
The preamble end is the end of the LONGEST qualifying silence — LibriVox
narrators leave their largest beat between credits and text. If no run
qualifies, there is no skip.

## Components

### PreambleDetector (new, `AudiobooksTV/Core/PreambleDetector.swift`)

Pure Foundation, unit-tested in the SPM target.

- `static func preambleEnd(windowRMS: [Float], windowDuration: Double) -> Double?`
  Implements the heuristic above with constants:
  `silenceFloorFraction = 0.2` (of median non-zero RMS),
  `minSilence = 0.8`, `minEnd = 8.0`, `maxEnd = 60.0`.
  Returns the offset in seconds, or nil.

### AudioAnalyzer (new, `AudiobooksTV/Services/AudioAnalyzer.swift`)

- `static func rmsWindows(fileURL: URL, windowDuration: Double, limit: Double) async throws -> [Float]`
  AVAssetReader over `timeRange` 0..limit, mono-mixed PCM float,
  RMS per window. Any decode error propagates; callers treat errors
  as "no skip".

### PreambleOffsetStore (new, `AudiobooksTV/Core/PreambleOffsetStore.swift`)

UserDefaults-backed cache of detected offsets, same shape as
ProgressStore. Unit-tested.

- Backing storage: `[String: Double]` persisted under key
  `"preambleOffsets.v1"`.
- `func offset(sectionID: String) -> Double?` — nil means "never
  analyzed"; a stored value of `0` means "analyzed, nothing to skip".
- `func save(offset: Double, sectionID: String)` — callers save `0`
  when detection found no preamble.

### PlayerView wiring

- In `startAudio()`, when the section starts fresh (`pendingSeekSeconds
  == 0` at entry), after the audio loads: spawn a task that reads the
  cached offset or (on miss) runs AudioAnalyzer + PreambleDetector on
  the local file, saves the result (0 on nil), then on the main actor:
  if the resolved offset is > 0, the same section is still loaded,
  `audio.currentTime < offset`, and the user has not manually seeked
  or changed sections meanwhile, `audio.seek(to: offset)`.
- Track the resolved offset in `@State preambleOffset: Double` (reset
  to 0 on section change) and pass it to the timeline as `leadIn`.

### ParagraphTimeline leadIn

- `init?(paragraphs: [String], duration: Double, leadIn: Double = 0)` —
  paragraph 0 starts at `leadIn`; the remaining `duration - leadIn` is
  split proportionally by character count as today. Guard: leadIn is
  clamped to `[0, duration * 0.5]` (a preamble is never half the
  section; clamping keeps a bogus cached value from wrecking sync).
  `paragraphIndex(at:)` clamps positions before `leadIn` to paragraph 0
  (unchanged clamp-to-first behavior).

## Error handling

- Decode failure, unreadable file, or detection nil → save 0, no skip,
  timeline leadIn 0 — exactly today's behavior.
- Detection runs at most once per section ever (cache), and its task is
  cancelled if the section changes before it finishes (no save on
  cancellation).

## Testing

- PreambleDetector unit tests on synthetic RMS arrays: finds the longest
  qualifying silence; ignores silences ending before 8 s; ignores runs
  shorter than 0.8 s; nil when no silence; all-zero input returns nil;
  end-of-longest-run offset math.
- ParagraphTimeline leadIn tests: paragraph 0 starts at leadIn; index at
  a position below leadIn clamps to 0; leadIn clamped at half duration;
  default leadIn 0 preserves existing behavior (existing tests must not
  change).
- PreambleOffsetStore tests: save/read round-trip, 0 sentinel, persistence
  across instances.
- AudioAnalyzer + PlayerView wiring verified manually in the simulator.
