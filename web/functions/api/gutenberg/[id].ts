import { gutenbergCandidates, parseEbookID } from "../lib/upstream";

/**
 * CORS proxy for Project Gutenberg plain text (no CORS headers upstream).
 * Tries the same candidate URLs as the tvOS GutenbergClient. Texts are
 * immutable: cached at the edge for 30 days.
 */
export const onRequestGet: PagesFunction = async ({ request, params }) => {
  const ebookID = parseEbookID(typeof params.id === "string" ? params.id : undefined);
  if (ebookID === null) return new Response("Bad request", { status: 400 });

  const cache = caches.default;
  const cacheKey = new Request(new URL(request.url).origin + `/api/gutenberg/${ebookID}`);
  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  for (const candidate of gutenbergCandidates(ebookID)) {
    const upstream = await fetch(candidate);
    if (!upstream.ok) continue;
    const response = new Response(upstream.body, {
      headers: {
        "content-type": "text/plain; charset=utf-8",
        "cache-control": "public, max-age=2592000",
      },
    });
    await cache.put(cacheKey, response.clone());
    return response;
  }
  return new Response("Not found on Project Gutenberg", { status: 404 });
};
