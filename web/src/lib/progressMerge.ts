/**
 * Synced listening progress. Positions are last-writer-wins per book by
 * updatedAt. Finished sections are a mark/tombstone set: a section is
 * finished iff its finishedMarks timestamp is newer than any
 * unfinishedMarks timestamp for the same key. Marks are never deleted, so
 * merging any two device states always converges without resurrecting
 * undone changes.
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
}

export function emptyProgress(): ProgressState {
  return { positions: {}, finishedMarks: {}, unfinishedMarks: {} };
}

export function sectionKey(bookID: number, sectionIndex: number): string {
  return `${bookID}#${sectionIndex}`;
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

export function mergeProgress(a: ProgressState, b: ProgressState): ProgressState {
  const positions = { ...a.positions };
  for (const [key, position] of Object.entries(b.positions)) {
    if (positions[key] === undefined || position.updatedAt > positions[key].updatedAt) {
      positions[key] = position;
    }
  }
  return {
    positions,
    finishedMarks: maxByKey(a.finishedMarks, b.finishedMarks),
    unfinishedMarks: maxByKey(a.unfinishedMarks, b.unfinishedMarks),
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
