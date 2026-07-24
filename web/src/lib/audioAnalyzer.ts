/** Analysis parameters mirroring the tvOS AudioAnalyzer usage. */
export const ANALYSIS_WINDOW_DURATION = 0.05;
export const ANALYSIS_LIMIT_SECONDS = 60;
/** 1.5 MB covers 60 s even at 192 kbps; most LibriVox files are 64/128 kbps. */
const LEADING_BYTES = 1_572_864;

/** RMS loudness per window. The trailing partial window is emitted (the
 * detector ignores array-end silence runs anyway). */
export function rmsWindows(
  samples: Float32Array,
  sampleRate: number,
  windowDuration: number
): number[] {
  const windowSamples = Math.max(1, Math.floor(sampleRate * windowDuration));
  const windows: number[] = [];
  let sumSquares = 0;
  let samplesInWindow = 0;
  for (let i = 0; i < samples.length; i++) {
    const sample = samples[i];
    sumSquares += sample * sample;
    samplesInWindow += 1;
    if (samplesInWindow === windowSamples) {
      windows.push(Math.sqrt(sumSquares / samplesInWindow));
      sumSquares = 0;
      samplesInWindow = 0;
    }
  }
  if (samplesInWindow > 0) windows.push(Math.sqrt(sumSquares / samplesInWindow));
  return windows;
}

/**
 * Range-fetches the leading bytes of an MP3 (archive.org serves CORS with
 * Range support), decodes them with the Web Audio API — browsers decode
 * truncated MP3s frame-by-frame — and returns RMS windows of the first
 * 60 s of channel 0. Throws on fetch/decode failure or abort; callers must
 * NOT cache an offset in that case.
 */
export async function analyzeLeadingRMS(url: string, signal: AbortSignal): Promise<number[]> {
  const response = await fetch(url, {
    headers: { Range: `bytes=0-${LEADING_BYTES - 1}` },
    signal,
  });
  if (!response.ok) throw new Error(`audio fetch failed: HTTP ${response.status}`);
  const bytes = await response.arrayBuffer();
  if (signal.aborted) throw new DOMException("aborted", "AbortError");

  const context = new AudioContext();
  try {
    const buffer = await context.decodeAudioData(bytes);
    if (signal.aborted) throw new DOMException("aborted", "AbortError");
    const limit = Math.min(buffer.length, Math.floor(ANALYSIS_LIMIT_SECONDS * buffer.sampleRate));
    const samples = buffer.getChannelData(0).subarray(0, limit);
    return rmsWindows(samples, buffer.sampleRate, ANALYSIS_WINDOW_DURATION);
  } finally {
    void context.close();
  }
}
