import { parseBooks, type Audiobook } from "./librivox";

/** Hardcoded home-screen shelves; `id` is the LibriVox genre name in the API query. */
export const SHELVES = [
  { id: "General Fiction", title: "Fiction" },
  { id: "Detective Fiction", title: "Mystery" },
  { id: "Science Fiction", title: "Sci-Fi" },
  { id: "Children's Fiction", title: "Children's" },
  { id: "History", title: "History" },
  { id: "Action & Adventure", title: "Adventure" },
  { id: "Poetry", title: "Poetry" },
] as const;

async function fetchBooks(params: Record<string, string>): Promise<Audiobook[]> {
  const response = await fetch(`/api/librivox?${new URLSearchParams(params)}`);
  if (!response.ok) {
    throw new Error(`LibriVox returned an error (HTTP ${response.status}). Try again.`);
  }
  return parseBooks(await response.json());
}

export function shelfBooks(genre: string, limit = 20): Promise<Audiobook[]> {
  return fetchBooks({ genre, limit: String(limit) });
}

/** Title + author queries in parallel, deduped by id (title hits first). */
export async function searchBooks(term: string): Promise<Audiobook[]> {
  const [byTitle, byAuthor] = await Promise.all([
    fetchBooks({ title: term }),
    fetchBooks({ author: term }),
  ]);
  const seen = new Set<number>();
  return [...byTitle, ...byAuthor].filter((b) => {
    if (seen.has(b.id)) return false;
    seen.add(b.id);
    return true;
  });
}

export async function bookByID(id: number): Promise<Audiobook | null> {
  return (await fetchBooks({ id: String(id) }))[0] ?? null;
}
