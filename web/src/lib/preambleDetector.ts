/**
 * Finds the end of the spoken LibriVox credits at the start of a section.
 *
 * Operates on RMS loudness windows of the clip's opening seconds. The
 * preamble end is the end of the longest silence whose end falls within
 * [MIN_END, MAX_END] — narrators leave their largest pause between the
 * credits and the chapter text.
 *
 * A silence run that is still open when the window array ends is dropped,
 * never scored: we can't tell whether it's a genuine pause or the end of
 * the analyzed clip/section. Treating that ambiguous run as "the" preamble
 * boundary has caused offsets near the end of short sections, seeking
 * playback to the end and making auto-advance skip the section outright.
 */
export const SILENCE_FLOOR_FRACTION = 0.2;
export const MIN_SILENCE = 0.8;
export const MIN_END = 8.0;
export const MAX_END = 60.0;

export function preambleEnd(windowRMS: number[], windowDuration: number): number | null {
  if (windowDuration <= 0 || windowRMS.length === 0) return null;
  const nonZero = windowRMS.filter((v) => v > 0).sort((a, b) => a - b);
  if (nonZero.length === 0) return null;
  const floor = nonZero[Math.floor(nonZero.length / 2)] * SILENCE_FLOOR_FRACTION;

  // Maximal runs of silent windows as {start, count}. A run still open when
  // the loop ends touches the array end and is intentionally dropped.
  const runs: Array<{ start: number; count: number }> = [];
  let runStart: number | null = null;
  windowRMS.forEach((rms, index) => {
    if (rms < floor) {
      if (runStart === null) runStart = index;
    } else if (runStart !== null) {
      runs.push({ start: runStart, count: index - runStart });
      runStart = null;
    }
  });

  const qualifying = runs.filter((run) => {
    const length = run.count * windowDuration;
    const end = (run.start + run.count) * windowDuration;
    return length >= MIN_SILENCE && end >= MIN_END && end <= MAX_END;
  });
  if (qualifying.length === 0) return null;
  const longest = qualifying.reduce((a, b) => (b.count > a.count ? b : a));
  return (longest.start + longest.count) * windowDuration;
}
