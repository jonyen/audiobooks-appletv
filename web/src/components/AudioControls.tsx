interface Props {
  playing: boolean;
  loading: boolean;
  currentTime: number;
  duration: number;
  rate: number;
  autoAdvance: boolean;
  finished: boolean;
  canPrev: boolean;
  canNext: boolean;
  bookTitle: string;
  onTogglePlay(): void;
  onPrev(): void;
  onNext(): void;
  onCycleRate(): void;
  onToggleAutoAdvance(): void;
  onToggleFinished(): void;
  onClose(): void;
}

function timeString(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) return "0:00";
  const total = Math.round(seconds);
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

export default function AudioControls(p: Props) {
  return (
    <div className="controls">
      <div className="controls-row">
        <button onClick={p.onClose} title="Back">⌄</button>
        <button onClick={p.onPrev} disabled={!p.canPrev} title="Previous section">⏮</button>
        <button onClick={p.onTogglePlay} disabled={p.loading} title="Play/Pause">
          {p.loading ? "…" : p.playing ? "⏸" : "▶"}
        </button>
        <button onClick={p.onNext} disabled={!p.canNext} title="Next section">⏭</button>
        <span className="controls-title dim">{p.bookTitle}</span>
        <button onClick={p.onCycleRate} title="Playback speed">{p.rate}×</button>
        <button
          onClick={p.onToggleAutoAdvance}
          className={p.autoAdvance ? "" : "inactive"}
          title="Auto-advance"
        >
          ↦
        </button>
        <button
          onClick={p.onToggleFinished}
          className={p.finished ? "gold" : "inactive"}
          title={p.finished ? "Mark as unfinished" : "Mark as finished"}
        >
          ✓
        </button>
      </div>
      <div className="controls-progress dim">
        <span>{timeString(p.currentTime)}</span>
        <progress value={Math.min(p.currentTime, p.duration || 1)} max={p.duration || 1} />
        <span>{timeString(p.duration)}</span>
      </div>
    </div>
  );
}
