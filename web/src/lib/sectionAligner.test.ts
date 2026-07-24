import { expect, test } from "vitest";
import { alignSections, matchedCount, normalizeTitle } from "./sectionAligner";

test("normalize converts Romans and strips punctuation", () => {
  expect(normalizeTitle("CHAPTER IV.")).toBe("chapter 4");
  expect(normalizeTitle("Chapter 04 — The Sea")).toBe("chapter 4 the sea");
  expect(normalizeTitle('"Stave One"')).toBe("stave one");
});

test("exact match", () => {
  const alignment = alignSections(["Chapter I", "Chapter II"], ["CHAPTER 1", "CHAPTER 2"]);
  expect(alignment).toEqual([0, 1]);
  expect(matchedCount(alignment)).toBe(2);
});

test("containment does not confuse prefix numbers", () => {
  // Section "Chapter 12" must not match chapter "CHAPTER 1".
  const alignment = alignSections(["12 - Chapter 12"], ["CHAPTER 1", "CHAPTER 12"]);
  expect(alignment).toEqual([1]);
});

test("unmatched section is null", () => {
  const alignment = alignSections(
    ["Translator's Preface", "Chapter 1"],
    ["CHAPTER 1", "CHAPTER 2"]
  );
  expect(alignment).toEqual([null, 0]);
  expect(matchedCount(alignment)).toBe(1);
});

test("positional fallback when counts equal and nothing matched", () => {
  const alignment = alignSections(
    ["Part the First", "Part the Second"],
    ["The Beginning", "The End"]
  );
  expect(alignment).toEqual([0, 1]);
});

test("TOC stubs do not win alignment", () => {
  const longBody = "prose ".repeat(100);
  const alignment = alignSections(
    ["Chapter 1", "Chapter 2"],
    ["CHAPTER I.", "CHAPTER II.", "CHAPTER I.", "CHAPTER II."],
    ["", "", longBody, longBody]
  );
  expect(alignment).toEqual([2, 3]);
});

test("bodies omitted keeps old behavior", () => {
  expect(alignSections(["Chapter I"], ["CHAPTER 1"])).toEqual([0]);
});
