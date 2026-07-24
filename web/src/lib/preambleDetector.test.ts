import { expect, test } from "vitest";
import { preambleEnd } from "./preambleDetector";

/** Builds an RMS array from [level, seconds] segments at 0.1s windows. */
function windows(segments: Array<[number, number]>): number[] {
  return segments.flatMap(([level, seconds]) => Array(Math.round(seconds * 10)).fill(level));
}

test("picks the longest qualifying silence", () => {
  // 10s speech, 1s pause, 9s speech, 2s pause (ends at 22s), 10s speech.
  const rms = windows([[1.0, 10], [0.0, 1], [1.0, 9], [0.0, 2], [1.0, 10]]);
  const end = preambleEnd(rms, 0.1)!;
  expect(Math.abs(end - 22.0)).toBeLessThan(0.11);
});

test("ignores silence ending before minEnd", () => {
  // Only pause ends at 4s — inside the credits, not after them.
  const rms = windows([[1.0, 2], [0.0, 2], [1.0, 26]]);
  expect(preambleEnd(rms, 0.1)).toBeNull();
});

test("ignores short silences", () => {
  // Pauses of 0.5s never qualify (minSilence 0.8).
  const rms = windows([[1.0, 10], [0.0, 0.5], [1.0, 10], [0.0, 0.5], [1.0, 10]]);
  expect(preambleEnd(rms, 0.1)).toBeNull();
});

test("null for no silence, all zero, or empty", () => {
  expect(preambleEnd(windows([[1.0, 30]]), 0.1)).toBeNull();
  expect(preambleEnd(windows([[0.0, 30]]), 0.1)).toBeNull();
  expect(preambleEnd([], 0.1)).toBeNull();
  expect(preambleEnd([1, 0, 1], 0)).toBeNull();
});

test("silence is relative to the median level", () => {
  // Quiet-but-voiced windows (0.5 of median 1.0) are NOT silence;
  // windows at 0.1 of median are.
  const rms = windows([[1.0, 10], [0.5, 2], [1.0, 5], [0.1, 1], [1.0, 12]]);
  const end = preambleEnd(rms, 0.1)!;
  expect(Math.abs(end - 18.0)).toBeLessThan(0.11);
});

test("ignores a silence run touching the array end", () => {
  // 10s speech followed by 2s silence with nothing after it — the run is
  // still open when the array ends. It must NOT be treated as the preamble
  // boundary: for a short section this silence is simply the clip's
  // trailing silence, not a pause before the chapter text.
  const rms = windows([[1.0, 10], [0.0, 2]]);
  expect(preambleEnd(rms, 0.1)).toBeNull();
});
