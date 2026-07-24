import { expect, test } from "vitest";
import { splitChapters } from "./chapterSplitter";

test("splits chapter headings", () => {
  const text = `CHAPTER I

It is a truth universally acknowledged.

CHAPTER II

Mr. Bennet was among the earliest.`;
  const chapters = splitChapters(text);
  expect(chapters.length).toBe(2);
  expect(chapters[0].title).toBe("CHAPTER I");
  expect(chapters[0].body.includes("universally acknowledged")).toBe(true);
  expect(chapters[1].title).toBe("CHAPTER II");
});

test("splits bare Roman numeral headings", () => {
  const text = "I.\n\nfirst body\n\nII.\n\nsecond body\n\nIII.\n\nthird body";
  const chapters = splitChapters(text);
  expect(chapters.length).toBe(3);
  expect(chapters[1].body).toBe("second body");
});

test("splits STAVE and LETTER headings", () => {
  const text = "STAVE ONE\n\nMarley was dead.\n\nSTAVE TWO\n\nThe Ghost.";
  expect(splitChapters(text).length).toBe(2);
});

test("requires a blank line before a heading", () => {
  // "II." inline in prose must not split.
  const text = "CHAPTER 1\n\nSee Act\nII. for details, and more prose here.\n\nCHAPTER 2\n\nbody";
  expect(splitChapters(text).length).toBe(2);
});

test("falls back to a single chapter", () => {
  const text = "Just one blob of prose with no headings.";
  const chapters = splitChapters(text);
  expect(chapters.length).toBe(1);
  expect(chapters[0].title).toBe("Full Text");
  expect(chapters[0].body).toBe(text);
});

test("handles CRLF line endings", () => {
  const text = "CHAPTER I\r\n\r\nfirst body\r\n\r\nCHAPTER II\r\n\r\nsecond body";
  const chapters = splitChapters(text);
  expect(chapters.length).toBe(2);
  expect(chapters[0].title).toBe("CHAPTER I");
  expect(chapters[1].body).toBe("second body");
});
