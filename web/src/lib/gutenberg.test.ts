import { expect, test } from "vitest";
import { ebookID, stripBoilerplate } from "./gutenberg";

test("extracts ID from common URL shapes", () => {
  expect(ebookID("http://www.gutenberg.org/etext/1342")).toBe(1342);
  expect(ebookID("https://www.gutenberg.org/ebooks/158")).toBe(158);
  expect(ebookID("https://www.gutenberg.org/files/76/76-h/76-h.htm")).toBe(76);
  expect(ebookID("https://www.gutenberg.org/cache/epub/2701/pg2701.txt")).toBe(2701);
});

test("rejects non-Gutenberg sources", () => {
  expect(ebookID("https://en.wikisource.org/wiki/Some_Book")).toBeNull();
  expect(ebookID("")).toBeNull();
});

test("strips boilerplate", () => {
  const raw = `The Project Gutenberg eBook of Example
junk license header

*** START OF THE PROJECT GUTENBERG EBOOK EXAMPLE ***

CHAPTER I

Actual content here.

*** END OF THE PROJECT GUTENBERG EBOOK EXAMPLE ***
more license junk`;
  const stripped = stripBoilerplate(raw);
  expect(stripped.startsWith("CHAPTER I")).toBe(true);
  expect(stripped.endsWith("Actual content here.")).toBe(true);
  expect(stripped.includes("license")).toBe(false);
});

test("handles THIS variant and missing markers", () => {
  const variant =
    "*** START OF THIS PROJECT GUTENBERG EBOOK X ***\nbody\n*** END OF THIS PROJECT GUTENBERG EBOOK X ***";
  expect(stripBoilerplate(variant)).toBe("body");
  expect(stripBoilerplate("no markers at all")).toBe("no markers at all");
});

test("strips boilerplate with CRLF endings", () => {
  const raw =
    "header junk\r\n*** START OF THE PROJECT GUTENBERG EBOOK JANE EYRE ***\r\n\r\nCHAPTER I\r\n\r\nThere was no possibility.\r\n\r\n*** END OF THE PROJECT GUTENBERG EBOOK JANE EYRE ***\r\nfooter junk";
  const stripped = stripBoilerplate(raw);
  expect(stripped.startsWith("CHAPTER I")).toBe(true);
  expect(stripped.endsWith("There was no possibility.")).toBe(true);
  expect(stripped.includes("footer")).toBe(false);
});
