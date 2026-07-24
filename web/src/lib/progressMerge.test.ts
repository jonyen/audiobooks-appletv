import { expect, test } from "vitest";
import {
  continueListening,
  emptyProgress,
  isFinished,
  mergeOffsets,
  mergeProgress,
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
