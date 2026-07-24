/**
 * Synced listening progress. Positions are last-writer-wins per book by
 * updatedAt. Finished sections and hidden books are mark/tombstone sets: a
 * section is finished iff its finishedMarks timestamp is newer than any
 * unfinishedMarks timestamp for the same key, and a book is hidden by the
 * same rule keyed on book ID alone. Marks are never deleted, so merging any
 * two device states always converges without resurrecting undone changes.
 */
export interface PlaybackPosition {
  bookID: number;
  bookTitle: string;
  coverURL: string | null;
  sectionIndex: number;
  seconds: number;
  updatedAt: number;
}

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

/**
 * Positions as stored in Firestore, normalized: the map key is the
 * authoritative bookID (tvOS writes no embedded bookID field), so inject
 * it from the key and never trust the embedded value.
 */
export function positionsFromSnapshot(raw: unknown): Record<string, PlaybackPosition> {
  const positions: Record<string, PlaybackPosition> = {};
  if (typeof raw !== "object" || raw === null) return positions;
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    const bookID = Number(key);
    if (!Number.isInteger(bookID) || typeof value !== "object" || value === null) continue;
    const v = value as Partial<PlaybackPosition>;
    if (typeof v.seconds !== "number" || typeof v.updatedAt !== "number" || typeof v.sectionIndex !== "number") continue;
    positions[key] = {
      bookID,
      bookTitle: typeof v.bookTitle === "string" ? v.bookTitle : "",
      coverURL: typeof v.coverURL === "string" ? v.coverURL : null,
      sectionIndex: v.sectionIndex,
      seconds: v.seconds,
      updatedAt: v.updatedAt,
    };
  }
  return positions;
}

export function sectionKey(bookID: number, sectionIndex: number): string {
  return `${bookID}#${sectionIndex}`;
}

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

/** MUST match the tvOS PreambleOffsetStore format: "\(book.id).\(sectionIndex)". */
export function preambleSectionID(bookID: number, sectionIndex: number): string {
  return `${bookID}.${sectionIndex}`;
}

export function isFinished(state: ProgressState, bookID: number, sectionIndex: number): boolean {
  const key = sectionKey(bookID, sectionIndex);
  const finished = state.finishedMarks[key];
  if (finished === undefined) return false;
  const unfinished = state.unfinishedMarks[key];
  return unfinished === undefined || finished > unfinished;
}

function maxByKey(a: Record<string, number>, b: Record<string, number>): Record<string, number> {
  const merged = { ...a };
  for (const [key, value] of Object.entries(b)) {
    if (merged[key] === undefined || value > merged[key]) merged[key] = value;
  }
  return merged;
}

/**
 * The newer of two positions by updatedAt. Exact-tie comparisons fall back
 * to content fields so the choice is deterministic and merge order never
 * matters (mergeProgress(a, b) === mergeProgress(b, a)).
 */
function newerPosition(x: PlaybackPosition, y: PlaybackPosition): PlaybackPosition {
  if (x.updatedAt !== y.updatedAt) return x.updatedAt > y.updatedAt ? x : y;
  if (x.seconds !== y.seconds) return x.seconds > y.seconds ? x : y;
  if (x.sectionIndex !== y.sectionIndex) return x.sectionIndex > y.sectionIndex ? x : y;
  if (x.bookTitle !== y.bookTitle) return x.bookTitle > y.bookTitle ? x : y;
  return (x.coverURL ?? "") >= (y.coverURL ?? "") ? x : y;
}

export function mergeProgress(a: ProgressState, b: ProgressState): ProgressState {
  const positions = { ...a.positions };
  for (const [key, position] of Object.entries(b.positions)) {
    positions[key] = positions[key] === undefined ? position : newerPosition(positions[key], position);
  }
  return {
    positions,
    finishedMarks: maxByKey(a.finishedMarks, b.finishedMarks),
    unfinishedMarks: maxByKey(a.unfinishedMarks, b.unfinishedMarks),
    hiddenMarks: maxByKey(a.hiddenMarks, b.hiddenMarks),
    unhiddenMarks: maxByKey(a.unhiddenMarks, b.unhiddenMarks),
  };
}

/** Newest-first positions for the Continue Listening shelf, capped at `limit`. */
export function continueListening(state: ProgressState, limit = 20): PlaybackPosition[] {
  return Object.values(state.positions)
    .sort((a, b) => b.updatedAt - a.updatedAt)
    .slice(0, limit);
}

/**
 * Preamble offsets are objective facts about the audio: union the maps,
 * keeping existing values in `a` (concurrent writes are equivalent).
 */
export function mergeOffsets(
  a: Record<string, number>,
  b: Record<string, number>
): Record<string, number> {
  return { ...b, ...a };
}
