import { expect, test } from "vitest";
import { parseRoman } from "./romanNumerals";

test("parses basic numerals", () => {
  expect(parseRoman("I")).toBe(1);
  expect(parseRoman("IV")).toBe(4);
  expect(parseRoman("IX")).toBe(9);
  expect(parseRoman("XIX")).toBe(19);
  expect(parseRoman("XLII")).toBe(42);
  expect(parseRoman("MCMXCIV")).toBe(1994);
});

test("case insensitive", () => {
  expect(parseRoman("xii")).toBe(12);
});

test("rejects invalid", () => {
  expect(parseRoman("")).toBeNull();
  expect(parseRoman("ABC")).toBeNull();
  expect(parseRoman("IL")).toBeNull();
  expect(parseRoman("chapter")).toBeNull();
});
