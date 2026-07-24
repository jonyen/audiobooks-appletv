import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";
import { chapterForSection, loadBookText, type BookText } from "../lib/bookText";
import { bookByID } from "../lib/catalog";
import { analyzeLeadingRMS, ANALYSIS_WINDOW_DURATION } from "../lib/audioAnalyzer";
import type { Audiobook } from "../lib/librivox";
import { makeParagraphTimeline, paragraphsFrom } from "../lib/paragraphTimeline";
import { preambleEnd } from "../lib/preambleDetector";
import { preambleSectionID } from "../lib/progressMerge";
import type { Preambles, Progress } from "../lib/progress";
import AudioControls from "./AudioControls";

const RATES = [1.0, 1.25, 1.5, 0.75];
const FOLLOW_SUSPEND_MS = 10_000;
const SAVE_DRIFT_SECONDS = 15;

export default function Player({
  progress,
  preambles,
}: {
  progress: Progress;
  preambles: Preambles;
}) {
  const { id, section } = useParams();
  const [search] = useSearchParams();
  const navigate = useNavigate();
  const bookID = parseInt(id ?? "", 10);
  const initialSection = parseInt(section ?? "0", 10) || 0;
  const initialSeconds = parseInt(search.get("t") ?? "0", 10) || 0;

  const [book, setBook] = useState<Audiobook | null | "loading" | "error">("loading");
  const [bookText, setBookText] = useState<BookText | null | "loading" | "error">("loading");
  const [textReloadKey, setTextReloadKey] = useState(0);
  const [sectionIndex, setSectionIndex] = useState(initialSection);
  const [playing, setPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [rate, setRate] = useState(1.0);
  const [autoAdvance, setAutoAdvance] = useState(true);
  const [preambleOffset, setPreambleOffset] = useState(0);
  const [audioError, setAudioError] = useState(false);

  const audioRef = useRef<HTMLAudioElement>(null);
  const paragraphRefs = useRef<Array<HTMLParagraphElement | null>>([]);
  const pendingSeekRef = useRef(initialSeconds);
  const pendingSkipRef = useRef<number | null>(null);
  const lastSavedRef = useRef(0);
  const followSuspendedUntilRef = useRef(0);

  const loadedBook = typeof book === "object" && book !== null ? book : null;

  // Load the book once per bookID. Kept independent from text loading so a
  // text-only retry never re-fetches (and never re-identifies) the book —
  // that identity feeds the preamble effect's deps, and a fresh object there
  // would look like a section change and re-trigger analysis mid-playback.
  useEffect(() => {
    let cancelled = false;
    bookByID(bookID)
      .then((b) => !cancelled && setBook(b ?? "error"))
      .catch(() => !cancelled && setBook("error"));
    return () => {
      cancelled = true;
    };
  }, [bookID]);

  // Load (and retry) the book text once the book itself has resolved. Keyed
  // on textReloadKey so "Try Again" only redoes this fetch, not the book
  // fetch above.
  useEffect(() => {
    if (!loadedBook) return;
    let cancelled = false;
    setBookText("loading");
    loadBookText(loadedBook)
      .then((t) => !cancelled && setBookText(t))
      .catch(() => !cancelled && setBookText("error"));
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loadedBook, textReloadKey]);

  const currentSection = loadedBook?.sections[sectionIndex] ?? null;
  const chapter =
    loadedBook && bookText !== "loading" && bookText !== "error" && bookText !== null
      ? chapterForSection(bookText, sectionIndex)
      : null;
  const paragraphs = useMemo(
    () => (chapter ? paragraphsFrom(chapter.body) : []),
    [chapter]
  );
  const timeline = useMemo(
    () => makeParagraphTimeline(paragraphs, duration, preambleOffset),
    [paragraphs, duration, preambleOffset]
  );
  const currentParagraphIndex = timeline?.paragraphIndex(currentTime) ?? null;

  const savePosition = useCallback(
    (seconds: number) => {
      if (!loadedBook) return;
      lastSavedRef.current = seconds;
      progress.savePosition({
        bookID: loadedBook.id,
        bookTitle: loadedBook.title,
        coverURL: loadedBook.coverURL,
        sectionIndex,
        seconds,
      });
    },
    [loadedBook, sectionIndex, progress]
  );

  // Latest-callback ref so the unmount-save effect below can run exactly
  // once (on true unmount) without re-subscribing on every section change.
  const savePositionRef = useRef(savePosition);
  savePositionRef.current = savePosition;

  /** Seek past the preamble only when sane: duration known, offset ≤ half
   * the section, playback not already past it. */
  const performClampedSeek = useCallback((offset: number) => {
    const audio = audioRef.current;
    if (!audio || !Number.isFinite(audio.duration) || audio.duration <= 0) return;
    if (offset > audio.duration * 0.5) return;
    if (audio.currentTime < offset) audio.currentTime = offset;
  }, []);

  // Preamble resolution per section start.
  useEffect(() => {
    if (!loadedBook || !currentSection) return;
    setPreambleOffset(0);
    pendingSkipRef.current = null;
    const sectionID = preambleSectionID(loadedBook.id, sectionIndex);
    const freshStart = pendingSeekRef.current === 0;

    if (!freshStart) {
      // Resuming mid-section: apply a cached leadIn so highlighting doesn't
      // drift by the preamble length, but never seek and never analyze.
      const cached = preambles.offset(sectionID);
      if (cached !== undefined && cached > 0) setPreambleOffset(cached);
      return;
    }

    const controller = new AbortController();
    void (async () => {
      let offset = preambles.offset(sectionID);
      if (offset === undefined) {
        let windows: number[];
        try {
          windows = await analyzeLeadingRMS(currentSection.listenURL, controller.signal);
        } catch {
          return; // fetch/decode failure or abort: never cache a result
        }
        if (controller.signal.aborted) return;
        offset = preambleEnd(windows, ANALYSIS_WINDOW_DURATION) ?? 0;
        preambles.saveOffset(sectionID, offset);
      }
      if (controller.signal.aborted || offset === undefined || offset <= 0) return;
      setPreambleOffset(offset);
      const audio = audioRef.current;
      if (audio && Number.isFinite(audio.duration) && audio.duration > 0) {
        performClampedSeek(offset);
      } else {
        // Duration unknown (metadata not loaded yet): defer the seek.
        pendingSkipRef.current = offset;
      }
    })();
    return () => controller.abort();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loadedBook, sectionIndex, currentSection]);

  // Synced offsets can arrive after the section starts (cold load, or another
  // device analyzed first): apply them to the timeline as they land. Never
  // seeks — seeking stays in the fresh-start analysis path.
  useEffect(() => {
    if (!loadedBook) return;
    const cached = preambles.offset(preambleSectionID(loadedBook.id, sectionIndex));
    if (cached !== undefined && cached > 0) setPreambleOffset(cached);
  }, [loadedBook, sectionIndex, preambles]);

  // Manual scroll suspends auto-follow.
  useEffect(() => {
    const suspend = () => {
      followSuspendedUntilRef.current = Date.now() + FOLLOW_SUSPEND_MS;
    };
    const onKey = (e: KeyboardEvent) => {
      if (["ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End", " "].includes(e.key)) {
        suspend();
      }
    };
    window.addEventListener("wheel", suspend, { passive: true });
    window.addEventListener("touchmove", suspend, { passive: true });
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("wheel", suspend);
      window.removeEventListener("touchmove", suspend);
      window.removeEventListener("keydown", onKey);
    };
  }, []);

  // Auto-scroll the narrated paragraph to the top of the view.
  useEffect(() => {
    if (!playing || currentParagraphIndex === null) return;
    if (Date.now() < followSuspendedUntilRef.current) return;
    paragraphRefs.current[currentParagraphIndex]?.scrollIntoView({
      behavior: "smooth",
      block: "start",
    });
  }, [currentParagraphIndex, playing]);

  // Save on unmount only (section changes are saved explicitly by
  // changeSection). Empty deps + a latest-callback ref keep this from
  // firing on every section transition, when audioRef would already point
  // at the newly-remounted <audio> for the next section.
  useEffect(() => {
    return () => {
      const audio = audioRef.current;
      if (audio && audio.currentTime > 0) savePositionRef.current(audio.currentTime);
    };
  }, []);

  if (book === "loading") return <main className="player"><p className="dim">Loading…</p></main>;
  if (book === "error" || !loadedBook || !currentSection) {
    return <main className="player"><p className="error">Couldn't load this book.</p></main>;
  }

  const changeSection = (next: number) => {
    savePosition(currentTime);
    pendingSeekRef.current = 0;
    lastSavedRef.current = 0;
    setCurrentTime(0);
    setDuration(0);
    setSectionIndex(next);
  };

  const finished = progress.isFinished(loadedBook.id, sectionIndex);

  return (
    <main className="player">
      <AudioControls
        playing={playing}
        loading={false}
        currentTime={currentTime}
        duration={duration}
        rate={rate}
        autoAdvance={autoAdvance}
        finished={finished}
        canPrev={sectionIndex > 0}
        canNext={sectionIndex < loadedBook.sections.length - 1}
        bookTitle={`${loadedBook.title} — ${currentSection.title}`}
        onTogglePlay={() => {
          const audio = audioRef.current;
          if (!audio) return;
          if (audio.paused) {
            // Restart from the top if the section already played to the end.
            if (duration > 0 && audio.currentTime >= duration - 0.5) audio.currentTime = 0;
            void audio.play();
          } else {
            audio.pause();
          }
        }}
        onPrev={() => changeSection(sectionIndex - 1)}
        onNext={() => changeSection(sectionIndex + 1)}
        onCycleRate={() => {
          const next = RATES[(RATES.indexOf(rate) + 1) % RATES.length];
          setRate(next);
          if (audioRef.current) audioRef.current.playbackRate = next;
        }}
        onToggleAutoAdvance={() => setAutoAdvance((v) => !v)}
        onToggleFinished={() => progress.toggleFinished(loadedBook.id, sectionIndex)}
        onClose={() => navigate(`/book/${loadedBook.id}`)}
      />

      <audio
        key={currentSection.id}
        ref={audioRef}
        src={currentSection.listenURL}
        autoPlay
        onLoadedMetadata={(e) => {
          const audio = e.currentTarget;
          setDuration(audio.duration);
          audio.playbackRate = rate;
          if (pendingSeekRef.current > 0) {
            audio.currentTime = pendingSeekRef.current;
            pendingSeekRef.current = 0;
          }
          if (pendingSkipRef.current !== null) {
            performClampedSeek(pendingSkipRef.current);
            pendingSkipRef.current = null;
          }
        }}
        onTimeUpdate={(e) => {
          const t = e.currentTarget.currentTime;
          setCurrentTime(t);
          if (Math.abs(t - lastSavedRef.current) > SAVE_DRIFT_SECONDS) savePosition(t);
        }}
        onPlay={() => {
          setPlaying(true);
          setAudioError(false);
        }}
        onPause={() => {
          setPlaying(false);
          const audio = audioRef.current;
          if (audio && audio.currentTime > 0 && !audio.ended) savePosition(audio.currentTime);
        }}
        onEnded={() => {
          progress.markFinished(loadedBook.id, sectionIndex);
          if (autoAdvance && sectionIndex < loadedBook.sections.length - 1) {
            changeSection(sectionIndex + 1);
          }
        }}
        onError={() => setAudioError(true)}
      />

      {audioError && (
        <p className="error">
          Audio failed to load.{" "}
          <button onClick={() => audioRef.current?.load()}>Try Again</button>
        </p>
      )}

      {chapter ? (
        <div className="reader">
          {paragraphs.map((paragraph, index) => (
            <p
              key={index}
              ref={(el) => {
                paragraphRefs.current[index] = el;
              }}
              className={playing && index !== currentParagraphIndex ? "para dimmed" : "para"}
            >
              {paragraph}
            </p>
          ))}
        </div>
      ) : bookText !== "loading" && bookText !== "error" && bookText !== null ? (
        <div className="reader">
          <p className="dim">This chapter couldn't be matched — showing the full book text.</p>
          {bookText.chapters.map((c, i) => (
            <section key={i}>
              {bookText.chapters.length > 1 && <h3>{c.title}</h3>}
              <p className="para">{c.body}</p>
            </section>
          ))}
        </div>
      ) : bookText === "loading" ? (
        <p className="dim reader">Loading text…</p>
      ) : bookText === "error" ? (
        <div className="reader">
          <p className="error">The book text could not be loaded.</p>
          <button onClick={() => setTextReloadKey((k) => k + 1)}>Try Again</button>
        </div>
      ) : (
        <div className="cover-only">
          {loadedBook.coverURL && <img src={loadedBook.coverURL} alt="" />}
          <p className="dim">Text unavailable for this book</p>
        </div>
      )}
    </main>
  );
}
