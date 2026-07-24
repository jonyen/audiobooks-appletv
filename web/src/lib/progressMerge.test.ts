import { expect, test } from "vitest";
import {
  bookKey,
  continueListening,
  emptyProgress,
  isFinished,
  isHidden,
  mergeOffsets,
  mergeProgress,
  positionsFromSnapshot,
  preambleSectionID,
  sectionKey,
  type PlaybackPosition,
  type ProgressState,
} from "./progressMerge";

const pos = (bookID: number, updatedAt: number, seconds = 10): PlaybackPosition => ({
  bookID,
  bookTitle: `Book ${bookID}`,
  coverURL: null,
  sectionIndex: 0,
  seconds,
  updatedAt,
});

const state = (partial: Partial<ProgressState>): ProgressState => ({
  ...emptyProgress(),
  ...partial,
});

test("key formats match tvOS", () => {
  expect(sectionKey(52, 3)).toBe("52#3");
  expect(preambleSectionID(52, 3)).toBe("52.3");
});

test("isFinished: mark alone wins; newer unmark wins; newer re-mark wins back", () => {
  expect(isFinished(state({ finishedMarks: { "52#3": 100 } }), 52, 3)).toBe(true);
  expect(isFinished(emptyProgress(), 52, 3)).toBe(false);
  const unmarked = state({ finishedMarks: { "52#3": 100 }, unfinishedMarks: { "52#3": 200 } });
  expect(isFinished(unmarked, 52, 3)).toBe(false);
  const remarked = state({ finishedMarks: { "52#3": 300 }, unfinishedMarks: { "52#3": 200 } });
  expect(isFinished(remarked, 52, 3)).toBe(true);
});

test("merge unions marks taking per-key maximums", () => {
  const a = state({ finishedMarks: { "1#0": 100, "52#3": 300 }, unfinishedMarks: { "52#3": 200 } });
  const b = state({ finishedMarks: { "2#0": 150, "52#3": 250 }, unfinishedMarks: { "52#3": 400 } });
  const merged = mergeProgress(a, b);
  expect(merged.finishedMarks).toEqual({ "1#0": 100, "2#0": 150, "52#3": 300 });
  expect(merged.unfinishedMarks).toEqual({ "52#3": 400 });
  expect(isFinished(merged, 1, 0)).toBe(true);
  expect(isFinished(merged, 52, 3)).toBe(false); // unmark at 400 beats re-mark at 300
});

test("stale unmark cannot resurrect a newer re-mark through merge", () => {
  const a = state({ finishedMarks: { "52#3": 300 }, unfinishedMarks: { "52#3": 200 } });
  const b = state({ finishedMarks: { "52#3": 100 }, unfinishedMarks: { "52#3": 200 } });
  expect(isFinished(mergeProgress(a, b), 52, 3)).toBe(true);
});

test("positions merge last-writer-wins per book", () => {
  const a = state({ positions: { "1": pos(1, 100, 42), "2": pos(2, 500) } });
  const b = state({ positions: { "1": pos(1, 300, 99), "3": pos(3, 200) } });
  const merged = mergeProgress(a, b);
  expect(merged.positions["1"].seconds).toBe(99); // newer write wins
  expect(merged.positions["2"].updatedAt).toBe(500);
  expect(merged.positions["3"].updatedAt).toBe(200);
});

test("continueListening sorts newest-first and caps at 20", () => {
  const positions: Record<string, PlaybackPosition> = {};
  for (let i = 1; i <= 25; i++) positions[String(i)] = pos(i, i * 10);
  const list = continueListening(state({ positions }));
  expect(list.length).toBe(20);
  expect(list[0].bookID).toBe(25);
  expect(list[19].bookID).toBe(6);
});

test("offsets merge as a union with existing values preserved", () => {
  expect(mergeOffsets({ "52.3": 14.5 }, { "52.3": 15.0, "52.4": 0 })).toEqual({
    "52.3": 14.5,
    "52.4": 0,
  });
});

test("positionsFromSnapshot injects bookID from the map key (tvOS writes none)", () => {
  const raw = {
    "52": { bookTitle: "Pride", coverURL: null, sectionIndex: 3, seconds: 42, updatedAt: 1000 },
    "bad": { bookTitle: "X", sectionIndex: 0, seconds: 1, updatedAt: 1 },
    "7": "not-an-object",
  };
  const positions = positionsFromSnapshot(raw);
  expect(Object.keys(positions)).toEqual(["52"]);
  expect(positions["52"].bookID).toBe(52);
  expect(continueListening({ ...emptyProgress(), positions })[0].bookID).toBe(52);
});

test("positionsFromSnapshot never trusts an embedded bookID", () => {
  const positions = positionsFromSnapshot({
    "52": { bookID: 999, bookTitle: "Pride", coverURL: null, sectionIndex: 3, seconds: 42, updatedAt: 1000 },
  });
  expect(positions["52"].bookID).toBe(52);
});

test("position merge is commutative on an exact updatedAt tie", () => {
  const a = state({ positions: { "1": pos(1, 100, 42) } });
  const b = state({ positions: { "1": { ...pos(1, 100, 99) } } });
  const ab = mergeProgress(a, b).positions["1"];
  const ba = mergeProgress(b, a).positions["1"];
  expect(ab).toEqual(ba);
  expect(ab.seconds).toBe(99); // deterministic winner: greater seconds on tie
});

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
