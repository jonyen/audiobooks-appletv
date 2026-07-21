import Foundation

struct TextChapter: Equatable {
    let title: String
    let body: String
}

enum ChapterSplitter {
    /// Splits a Gutenberg plain text into chapters by heading lines.
    /// A heading is a short line, preceded by a blank line (or text start),
    /// matching a chapter-keyword pattern or a bare Roman/Arabic numeral.
    static func split(_ text: String) -> [TextChapter] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var headingIndices: [Int] = []

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.count <= 80 else { continue }
            let previousBlank = i == 0
                || lines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty
            guard previousBlank, isHeading(trimmed) else { continue }
            headingIndices.append(i)
        }

        guard headingIndices.count >= 2 else {
            return [TextChapter(title: "Full Text", body: normalized)]
        }

        var chapters: [TextChapter] = []
        for (n, start) in headingIndices.enumerated() {
            let end = n + 1 < headingIndices.count ? headingIndices[n + 1] : lines.count
            let title = lines[start].trimmingCharacters(in: .whitespaces)
            let body = lines[(start + 1)..<end]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            chapters.append(TextChapter(title: title, body: body))
        }
        return chapters
    }

    static func isHeading(_ line: String) -> Bool {
        if line.firstMatch(of: #/^(?i:chapter|book|part|letter|stave|canto)\s+(\d+|[IVXLCDMivxlcdm]+|[A-Za-z]+)\b/#) != nil {
            return true
        }
        if let match = line.firstMatch(of: #/^([IVXLCDM]+)\.?\s*$/#),
           RomanNumerals.parse(String(match.1)) != nil {
            return true
        }
        if line.firstMatch(of: #/^(\d+)\.?\s*$/#) != nil {
            return true
        }
        return false
    }
}
