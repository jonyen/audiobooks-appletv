import { Link } from "react-router-dom";
import type { Audiobook } from "../lib/librivox";
import { hasText } from "../lib/gutenberg";

/** Cover card; audio-only books (no Gutenberg text) render dimmed, as on tvOS. */
export default function BookCard({ book }: { book: Audiobook }) {
  return (
    <Link to={`/book/${book.id}`} className={`card${hasText(book) ? "" : " card-dimmed"}`}>
      {book.coverURL ? (
        <img src={book.coverURL} alt="" loading="lazy" />
      ) : (
        <div className="card-placeholder">📖</div>
      )}
      <span className="card-title">{book.title}</span>
      <span className="card-authors">{book.authors}</span>
    </Link>
  );
}
