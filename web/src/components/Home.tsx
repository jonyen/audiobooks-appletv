import { useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { signOutUser } from "../lib/firebase";
import type { Audiobook } from "../lib/librivox";
import { SHELVES, shelfBooks } from "../lib/catalog";
import type { Progress } from "../lib/progress";
import BookCard from "./BookCard";

export default function Home({ progress }: { progress: Progress }) {
  return (
    <main className="library">
      <header className="library-header">
        <h1>Audiobooks</h1>
        <nav>
          <Link to="/search">Search</Link>
          <button onClick={() => void signOutUser()}>Sign out</button>
        </nav>
      </header>

      {progress.list.length > 0 && (
        <section>
          <h2>Continue Listening</h2>
          <div className="shelf-row">
            {progress.list.map((p) => (
              <Link
                key={p.bookID}
                to={`/book/${p.bookID}/play/${p.sectionIndex}?t=${Math.floor(p.seconds)}`}
                className="card"
              >
                {p.coverURL ? <img src={p.coverURL} alt="" /> : <div className="card-placeholder">📖</div>}
                <span className="card-title">{p.bookTitle}</span>
                <span className="card-authors">Section {p.sectionIndex + 1}</span>
              </Link>
            ))}
          </div>
        </section>
      )}

      {SHELVES.map((shelf) => (
        <ShelfRow key={shelf.id} genre={shelf.id} title={shelf.title} />
      ))}
    </main>
  );
}

function ShelfRow({ genre, title }: { genre: string; title: string }) {
  const [books, setBooks] = useState<Audiobook[] | "error" | null>(null);
  useEffect(() => {
    let cancelled = false;
    shelfBooks(genre)
      .then((b) => !cancelled && setBooks(b))
      .catch(() => !cancelled && setBooks("error"));
    return () => {
      cancelled = true;
    };
  }, [genre]);

  return (
    <section>
      <h2>{title}</h2>
      {books === null && <p className="dim">Loading…</p>}
      {books === "error" && <p className="dim">Couldn't load this shelf.</p>}
      {Array.isArray(books) && (
        <div className="shelf-row">
          {books.map((book) => (
            <BookCard key={book.id} book={book} />
          ))}
        </div>
      )}
    </section>
  );
}
