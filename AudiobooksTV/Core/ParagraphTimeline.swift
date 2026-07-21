import Foundation

/// Estimated narration start times for each paragraph of a chapter.
///
/// LibriVox audio has no timing metadata, so times are estimated by
/// splitting the section's duration across paragraphs in proportion to
/// their character counts. Recordings open with a short spoken preamble,
/// so early paragraphs run a few seconds behind the estimate; paragraph
/// granularity absorbs the drift.
struct ParagraphTimeline {
    private struct Entry {
        let start: Double
        let end: Double
    }

    private let entries: [Entry]

    /// Splits a chapter body into paragraphs on blank lines (lines that are
    /// empty or whitespace-only), trimming each paragraph and dropping
    /// empties. Handles CRLF input.
    static func paragraphs(from body: String) -> [String] {
        body.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .split(whereSeparator: { $0.trimmingCharacters(in: .whitespaces).isEmpty })
            .map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    init?(paragraphs: [String], duration: Double, leadIn: Double = 0) {
        guard duration.isFinite, duration > 0, !paragraphs.isEmpty else { return nil }
        let counts = paragraphs.map(\.count)
        let total = counts.reduce(0, +)
        guard total > 0 else { return nil }

        // A preamble is never half the section; clamping keeps a bogus
        // cached offset from wrecking the whole timeline.
        let clampedLeadIn = min(max(0, leadIn), duration * 0.5)
        let spoken = duration - clampedLeadIn
        var start = clampedLeadIn
        var entries: [Entry] = []
        for count in counts {
            let length = spoken * Double(count) / Double(total)
            entries.append(Entry(start: start, end: start + length))
            start += length
        }
        self.entries = entries
    }

    /// The paragraph being narrated at a playback position. Positions before
    /// zero clamp to the first paragraph; positions at or past the end clamp
    /// to the last.
    func paragraphIndex(at seconds: Double) -> Int? {
        guard let last = entries.last else { return nil }
        if let first = entries.first, seconds < first.start { return 0 }
        if seconds >= last.end { return entries.count - 1 }
        return entries.firstIndex { seconds >= $0.start && seconds < $0.end }
    }
}
