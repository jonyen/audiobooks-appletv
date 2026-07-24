import { Link } from "react-router-dom";
import type { Audiobook } from "../lib/librivox";
import { hasText } from "../lib/gutenberg";

/**
 * Cover card; audio-only books (no Gutenberg text) render dimmed, as on
 * tvOS. `hidden` is only ever true in search results — Home filters hidden
 * books out entirely — and marks the card so it can be unhidden from there.
 */
export default function BookCard({
  book,
  hidden = false,
  onToggleHidden,
}: {
  book: Audiobook;
  hidden?: boolean;
  onToggleHidden?: (bookID: number) => void;
}) {
  return (
    <div className={`card-wrap${hidden ? " card-hidden" : ""}`}>
      <Link to={`/book/${book.id}`} className={`card${hasText(book) ? "" : " card-dimmed"}`}>
        {book.coverURL ? (
          <img src={book.coverURL} alt="" loading="lazy" />
        ) : (
          <div className="card-placeholder">📖</div>
        )}
        <span className="card-title">{book.title}</span>
        <span className="card-authors">{book.authors}</span>
      </Link>
      {hidden && <span className="card-badge">Hidden</span>}
      {onToggleHidden && (
        <button
          type="button"
          className="card-hide"
          title={hidden ? "Unhide this book" : "Hide this book"}
          aria-label={hidden ? "Unhide this book" : "Hide this book"}
          onClick={() => onToggleHidden(book.id)}
        >
          {hidden ? "↺" : "✕"}
        </button>
      )}
    </div>
  );
}
