import Foundation

/// Finds the end of the spoken LibriVox credits at the start of a section.
///
/// Operates on RMS loudness windows of the clip's opening seconds. The
/// preamble end is the end of the longest silence whose end falls within
/// [minEnd, maxEnd] — narrators leave their largest pause between the
/// credits and the chapter text.
enum PreambleDetector {
    static let silenceFloorFraction: Float = 0.2
    static let minSilence = 0.8
    static let minEnd = 8.0
    static let maxEnd = 60.0

    static func preambleEnd(windowRMS: [Float], windowDuration: Double) -> Double? {
        guard windowDuration > 0, !windowRMS.isEmpty else { return nil }
        let nonZero = windowRMS.filter { $0 > 0 }.sorted()
        guard !nonZero.isEmpty else { return nil }
        let floor = nonZero[nonZero.count / 2] * silenceFloorFraction

        // Collect maximal runs of silent windows as (startIndex, count).
        var runs: [(start: Int, count: Int)] = []
        var runStart: Int?
        for (index, rms) in windowRMS.enumerated() {
            if rms < floor {
                if runStart == nil { runStart = index }
            } else if let start = runStart {
                runs.append((start, index - start))
                runStart = nil
            }
        }
        if let start = runStart {
            runs.append((start, windowRMS.count - start))
        }

        let qualifying = runs.filter { run in
            let length = Double(run.count) * windowDuration
            let end = Double(run.start + run.count) * windowDuration
            return length >= minSilence && end >= minEnd && end <= maxEnd
        }
        guard let longest = qualifying.max(by: { $0.count < $1.count }) else { return nil }
        return Double(longest.start + longest.count) * windowDuration
    }
}
