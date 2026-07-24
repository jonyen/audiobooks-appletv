import { expect, test } from "vitest";
import { makeParagraphTimeline, paragraphsFrom } from "./paragraphTimeline";

// Splitting

test("splits on blank lines", () => {
  const body = "First paragraph\nstill first.\n\nSecond paragraph.";
  expect(paragraphsFrom(body)).toEqual(["First paragraph\nstill first.", "Second paragraph."]);
});

test("handles CRLF and whitespace-only blank lines", () => {
  const body = "One.\r\n \r\nTwo.\r\n\r\n\r\nThree.";
  expect(paragraphsFrom(body)).toEqual(["One.", "Two.", "Three."]);
});

test("drops empties and trims whitespace", () => {
  expect(paragraphsFrom("\n\n  Alpha.  \n\n\n")).toEqual(["Alpha."]);
});

// Timeline

test("starts proportional to character counts", () => {
  // 10 chars then 30 chars over 40s: starts at 0 and 10.
  const timeline = makeParagraphTimeline(["a".repeat(10), "b".repeat(30)], 40)!;
  expect(timeline.paragraphIndex(0)).toBe(0);
  expect(timeline.paragraphIndex(9.9)).toBe(0);
  expect(timeline.paragraphIndex(10.1)).toBe(1);
  expect(timeline.paragraphIndex(39)).toBe(1);
});

test("clamps outside duration", () => {
  const timeline = makeParagraphTimeline(["aaa", "bbb"], 10)!;
  expect(timeline.paragraphIndex(-5)).toBe(0);
  expect(timeline.paragraphIndex(99)).toBe(1);
});

test("null for empty paragraphs or bad duration", () => {
  expect(makeParagraphTimeline([], 10)).toBeNull();
  expect(makeParagraphTimeline(["a"], 0)).toBeNull();
  expect(makeParagraphTimeline(["a"], Infinity)).toBeNull();
});

test("leadIn shifts all starts", () => {
  // leadIn 10 over 40s, paragraphs 10 and 30 chars:
  // paragraph 0 spans 10..17.5, paragraph 1 spans 17.5..40.
  const timeline = makeParagraphTimeline(["a".repeat(10), "b".repeat(30)], 40, 10)!;
  expect(timeline.paragraphIndex(12)).toBe(0);
  expect(timeline.paragraphIndex(18)).toBe(1);
});

test("positions before leadIn clamp to the first paragraph", () => {
  const timeline = makeParagraphTimeline(["aaa", "bbb"], 40, 10)!;
  expect(timeline.paragraphIndex(0)).toBe(0);
  expect(timeline.paragraphIndex(9.9)).toBe(0);
});

test("leadIn clamps to half duration; negative behaves as 0", () => {
  // leadIn 30 of 40s clamps to 20: position 19 is still before paragraph 0.
  const clamped = makeParagraphTimeline(["aaa", "bbb"], 40, 30)!;
  expect(clamped.paragraphIndex(19)).toBe(0);
  expect(clamped.paragraphIndex(31)).toBe(1);
  const negative = makeParagraphTimeline(["aaa", "bbb"], 10, -5)!;
  expect(negative.paragraphIndex(6)).toBe(1);
});
