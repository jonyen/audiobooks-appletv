import { useState } from "react";
import { Link } from "react-router-dom";
import type { Audiobook } from "../lib/librivox";
import { hasText } from "../lib/gutenberg";
import { searchBooks } from "../lib/catalog";
import type { Progress } from "../lib/progress";
import BookCard from "./BookCard";

export default function Search({ progress }: { progress: Progress }) {
  const [term, setTerm] = useState("");
  const [results, setResults] = useState<Audiobook[] | null>(null);
  const [readAlongOnly, setReadAlongOnly] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const shown = results?.filter((b) => !readAlongOnly || hasText(b));

  return (
    <main className="library">
      <header className="library-header">
        <h1>Search</h1>
        <nav>
          <Link to="/">Home</Link>
        </nav>
      </header>

      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (!term.trim()) return;
          setBusy(true);
          setError(null);
          searchBooks(term.trim())
            .then(setResults)
            .catch((err: Error) => setError(err.message))
            .finally(() => setBusy(false));
        }}
      >
        <input
          value={term}
          onChange={(e) => setTerm(e.target.value)}
          placeholder="Title or author"
          autoFocus
        />
        <button type="submit" disabled={busy}>
          {busy ? "Searching…" : "Search"}
        </button>
        <label className="dim">
          <input
            type="checkbox"
            checked={readAlongOnly}
            onChange={(e) => setReadAlongOnly(e.target.checked)}
          />{" "}
          Read-along only
        </label>
      </form>

      {error && <p className="error">{error}</p>}
      {shown && shown.length === 0 && <p className="dim">No results.</p>}
      {shown && (
        <div className="shelf-grid">
          {shown.map((book) => (
            <BookCard
              key={book.id}
              book={book}
              hidden={progress.isHidden(book.id)}
              onToggleHidden={progress.toggleHidden}
            />
          ))}
        </div>
      )}
    </main>
  );
}
