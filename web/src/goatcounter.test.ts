import { describe, expect, it } from "vitest";
import indexHtml from "../index.html?raw";

// Anonymous, cookieless, aggregate visit counts via GoatCounter; no personal data.
const GOATCOUNTER_TAGS = /<script\b[^>]*\bdata-goatcounter="[^"]*"[^>]*><\/script>/g;

describe("visit counting", () => {
  it("loads GoatCounter once, for the audiobooks site, pinned by SRI", () => {
    const tags = indexHtml.match(GOATCOUNTER_TAGS) ?? [];
    expect(tags).toHaveLength(1);
    const tag = tags[0] ?? "";
    expect(tag).toContain('data-goatcounter="https://jonyen-audiobooks.goatcounter.com/count"');
    expect(tag).toContain('src="https://gc.zgo.at/count.v5.js"');
    expect(tag).toMatch(/\sasync[\s>]/);
    expect(tag).toContain('crossorigin="anonymous"');
    expect(tag).toContain(
      'integrity="sha384-atnOLvQb9t+jTSipvd75X2yginT4PjVbqDdlJAmxMm+wYElFmeR6EmLP5bYeoRVQ"',
    );
    // One path for the whole app, so a listener counts once per visit.
    const settings = tag.match(/data-goatcounter-settings='([^']*)'/);
    expect(JSON.parse(settings?.[1] ?? "null")).toEqual({ path: "/" });
  });
});
