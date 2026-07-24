import { librivoxUpstreamURL } from "./lib/upstream";

/**
 * CORS proxy for the LibriVox catalog API (which sends no CORS headers).
 * Public-domain catalog data: cached at the edge for a day, keyed on the
 * canonicalized upstream URL so param order doesn't fragment the cache.
 */
export const onRequestGet: PagesFunction = async ({ request }) => {
  const upstreamURL = librivoxUpstreamURL(new URL(request.url).searchParams);
  const cache = caches.default;
  const cacheKey = new Request(upstreamURL);

  const cached = await cache.match(cacheKey);
  if (cached) return cached;

  const upstream = await fetch(upstreamURL);
  if (!upstream.ok) return new Response("Upstream error", { status: 502 });
  const response = new Response(upstream.body, {
    headers: {
      "content-type": "application/json",
      "cache-control": "public, max-age=86400",
    },
  });
  await cache.put(cacheKey, response.clone());
  return response;
};
