import { expect, test } from "vitest";
import { firstOkResponse, gutenbergCandidates, librivoxUpstreamURL, parseEbookID } from "./upstream";

test("librivox URL keeps only allowlisted params and appends format", () => {
  const url = librivoxUpstreamURL(
    new URLSearchParams({ genre: "General Fiction", limit: "20", evil: "https://attacker.example" })
  );
  const parsed = new URL(url);
  expect(parsed.origin).toBe("https://librivox.org");
  expect(parsed.pathname).toBe("/api/feed/audiobooks");
  expect(parsed.searchParams.get("genre")).toBe("General Fiction");
  expect(parsed.searchParams.get("limit")).toBe("20");
  expect(parsed.searchParams.get("evil")).toBeNull();
  expect(parsed.searchParams.get("format")).toBe("json");
  expect(parsed.searchParams.get("extended")).toBe("1");
});

test("gutenberg candidates mirror the tvOS client order", () => {
  expect(gutenbergCandidates(1342)).toEqual([
    "https://www.gutenberg.org/cache/epub/1342/pg1342.txt",
    "https://www.gutenberg.org/files/1342/1342-0.txt",
    "https://www.gutenberg.org/files/1342/1342.txt",
  ]);
});

test("parseEbookID accepts only positive integers", () => {
  expect(parseEbookID("1342")).toBe(1342);
  expect(parseEbookID("0")).toBeNull();
  expect(parseEbookID("12a")).toBeNull();
  expect(parseEbookID("../etc")).toBeNull();
  expect(parseEbookID(undefined)).toBeNull();
});

test("firstOkResponse returns the first ok response, skipping earlier failures", async () => {
  const requested: string[] = [];
  const fetcher = async (url: string) => {
    requested.push(url);
    if (url === "a") return new Response("nope", { status: 404 });
    if (url === "b") return new Response("hi", { status: 200 });
    throw new Error("should not reach c");
  };
  const response = await firstOkResponse(["a", "b", "c"], fetcher);
  expect(response).not.toBeNull();
  expect(await response!.text()).toBe("hi");
  expect(requested).toEqual(["a", "b"]);
});

test("firstOkResponse returns null when every candidate fails", async () => {
  const fetcher = async () => new Response("nope", { status: 404 });
  const response = await firstOkResponse(["a", "b"], fetcher);
  expect(response).toBeNull();
});
