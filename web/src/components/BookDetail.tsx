import { useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import type { Audiobook } from "../lib/librivox";
import { bookByID } from "../lib/catalog";
import { loadBookText, matchSummary, type BookText } from "../lib/bookText";
import type { Progress } from "../lib/progress";

export default function BookDetail({ progress }: { progress: Progress }) {
  const { id } = useParams();
  const bookID = parseInt(id ?? "", 10);
  const [book, setBook] = useState<Audiobook | null | "loading" | "error">("loading");
  const [text, setText] = useState<BookText | null | "loading">("loading");

  useEffect(() => {
    let cancelled = false;
    setBook("loading");
    setText("loading");
    bookByID(bookID)
      .then((b) => {
        if (cancelled) return;
        setBook(b);
        if (b) {
          loadBookText(b)
            .then((t) => !cancelled && setText(t))
            .catch(() => !cancelled && setText(null));
        } else {
          setText(null);
        }
      })
      .catch(() => !cancelled && setBook("error"));
    return () => {
      cancelled = true;
    };
  }, [bookID]);

  if (book === "loading") return <main className="library"><p className="dim">Loading…</p></main>;
  if (book === "error" || book === null) {
    return <main className="library"><p className="error">Couldn't load this book.</p></main>;
  }

  const saved = progress.positionFor(book.id);

  return (
    <main className="library">
      <header className="library-header">
        <h1>{book.title}</h1>
        <nav>
          <Link to="/">Home</Link>
        </nav>
      </header>

      <div className="detail">
        {book.coverURL && <img className="detail-cover" src={book.coverURL} alt="" />}
        <div>
          <p className="dim">{book.authors}</p>
          <p>{book.description}</p>
          <p className="dim">
            {text === "loading" && "Checking read-along availability…"}
            {text === null && "Audio-only — no matching text found."}
            {text !== "loading" && text !== null && matchSummary(text)}
          </p>
          {saved && (
            <Link
              className="resume"
              to={`/book/${book.id}/play/${saved.sectionIndex}?t=${Math.floor(saved.seconds)}`}
            >
              ▶ Continue — Section {saved.sectionIndex + 1}
            </Link>
          )}
          <button
            type="button"
            className="hide-toggle"
            onClick={() => progress.toggleHidden(book.id)}
          >
            {progress.isHidden(book.id) ? "Unhide from shelves" : "Hide from shelves"}
          </button>
        </div>
      </div>

      <h2>Sections</h2>
      <ol className="sections">
        {book.sections.map((section, index) => (
          <li key={section.id}>
            <Link
              to={`/book/${book.id}/play/${index}`}
              className={progress.isFinished(book.id, index) ? "finished" : ""}
            >
              {section.title}
            </Link>
            <span className="dim"> {Math.floor(section.playtimeSeconds / 60)} min</span>
          </li>
        ))}
      </ol>
    </main>
  );
}
