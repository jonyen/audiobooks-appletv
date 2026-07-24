export interface AudioSection {
  id: number;
  number: number;
  title: string;
  listenURL: string;
  playtimeSeconds: number;
}

export interface Audiobook {
  id: number;
  title: string;
  authors: string;
  description: string;
  genres: string[];
  coverURL: string | null;
  textSourceURL: string | null;
  totalTimeSeconds: number;
  sections: AudioSection[];
}

/** Swift's Int("…"): the whole string must be an integer, else null. */
function strictInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isInteger(value)) return value;
  if (typeof value === "string" && /^-?\d+$/.test(value)) return parseInt(value, 10);
  return null;
}

const str = (value: unknown): string | null => (typeof value === "string" ? value : null);

export function stripHTML(s: string): string {
  return s.replace(/<[^>]+>/g, "").trim();
}

function coverURL(coverart: unknown, iarchive: unknown): string | null {
  const jpg = str(coverart);
  if (jpg) return jpg;
  const archive = str(iarchive);
  if (archive) {
    try {
      const identifier = new URL(archive).pathname.split("/").filter(Boolean).pop();
      if (identifier) return `https://archive.org/services/img/${identifier}`;
    } catch {
      /* not a URL — fall through */
    }
  }
  return null;
}

/* eslint-disable @typescript-eslint/no-explicit-any */
function makeBook(dto: any): Audiobook | null {
  const id = strictInt(dto?.id);
  if (id === null) return null;

  const authors = ((dto.authors ?? []) as any[])
    .map((a) =>
      [str(a?.first_name), str(a?.last_name)]
        .map((part) => part?.trim() ?? "")
        .filter((part) => part.length > 0)
        .join(" ")
    )
    .filter((name) => name.length > 0);

  const sections = ((dto.sections ?? []) as any[]).flatMap((s): AudioSection[] => {
    const sectionID = strictInt(s?.id);
    const listenURL = str(s?.listen_url);
    if (sectionID === null || !listenURL) return [];
    return [
      {
        id: sectionID,
        number: strictInt(s?.section_number) ?? 0,
        title: str(s?.title) ?? "Section",
        listenURL,
        playtimeSeconds: strictInt(s?.playtime) ?? 0,
      },
    ];
  });

  const textSource = str(dto.url_text_source);
  return {
    id,
    title: str(dto.title) ?? "Untitled",
    authors: authors.join(", "),
    description: stripHTML(str(dto.description) ?? ""),
    genres: ((dto.genres ?? []) as any[]).map((g) => str(g?.name)).filter((n): n is string => !!n),
    coverURL: coverURL(dto.coverart_jpg, dto.url_iarchive),
    textSourceURL: textSource && textSource.length > 0 ? textSource : null,
    totalTimeSeconds: strictInt(dto.totaltimesecs) ?? 0,
    sections,
  };
}

/** Parses the LibriVox API envelope. Error payloads ({"error": …}) parse as []. */
export function parseBooks(payload: unknown): Audiobook[] {
  const books = (payload as any)?.books;
  if (!Array.isArray(books)) return [];
  return books.map(makeBook).filter((b): b is Audiobook => b !== null);
}
