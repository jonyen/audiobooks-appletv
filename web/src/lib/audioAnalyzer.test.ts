import { expect, test } from "vitest";
import { rmsWindows } from "./audioAnalyzer";

test("computes RMS per full window", () => {
  // 1s of amplitude 1.0 then 1s of silence at 10 samples/s, 0.5s windows.
  const samples = new Float32Array([...Array(10).fill(1), ...Array(10).fill(0)]);
  const windows = rmsWindows(samples, 10, 0.5);
  expect(windows.length).toBe(4);
  expect(windows[0]).toBeCloseTo(1.0, 5);
  expect(windows[1]).toBeCloseTo(1.0, 5);
  expect(windows[2]).toBeCloseTo(0.0, 5);
});

test("emits a final partial window", () => {
  const samples = new Float32Array(Array(12).fill(0.5));
  const windows = rmsWindows(samples, 10, 1.0);
  expect(windows.length).toBe(2); // one full 10-sample window + 2-sample remainder
  expect(windows[1]).toBeCloseTo(0.5, 5);
});

test("empty input produces no windows", () => {
  expect(rmsWindows(new Float32Array(0), 16000, 0.05)).toEqual([]);
});
