/** Query params forwarded to the LibriVox catalog API. Everything else is dropped. */
const LIBRIVOX_PARAMS = ["id", "genre", "title", "author", "limit", "offset"] as const;

export function librivoxUpstreamURL(params: URLSearchParams): string {
  const upstream = new URL("https://librivox.org/api/feed/audiobooks");
  for (const key of LIBRIVOX_PARAMS) {
    const value = params.get(key);
    if (value !== null) upstream.searchParams.set(key, value);
  }
  upstream.searchParams.set("format", "json");
  upstream.searchParams.set("extended", "1");
  return upstream.toString();
}

/** Candidate plain-text URLs, in the same order the tvOS GutenbergClient tries. */
export function gutenbergCandidates(ebookID: number): string[] {
  return [
    `https://www.gutenberg.org/cache/epub/${ebookID}/pg${ebookID}.txt`,
    `https://www.gutenberg.org/files/${ebookID}/${ebookID}-0.txt`,
    `https://www.gutenberg.org/files/${ebookID}/${ebookID}.txt`,
  ];
}

export function parseEbookID(raw: string | undefined): number | null {
  if (!raw || !/^[1-9]\d*$/.test(raw)) return null;
  return parseInt(raw, 10);
}

/** Tries candidates in order with the given fetcher; returns the first ok Response or null. */
export async function firstOkResponse(
  candidates: string[],
  fetcher: (url: string) => Promise<Response>
): Promise<Response | null> {
  for (const candidate of candidates) {
    const response = await fetcher(candidate);
    if (response.ok) return response;
  }
  return null;
}
