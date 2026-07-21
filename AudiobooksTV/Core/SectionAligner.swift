import Foundation

struct ChapterAlignment: Equatable {
    /// chapterIndexBySection[i] is the chapter index for audio section i,
    /// or nil when no text chapter matched.
    let chapterIndexBySection: [Int?]

    var matchedCount: Int { chapterIndexBySection.compactMap { $0 }.count }
}

enum SectionAligner {
    /// Lowercases, splits on non-alphanumerics, converts Roman-numeral tokens
    /// and zero-padded numbers to plain Arabic, rejoins with single spaces.
    static func normalize(_ title: String) -> String {
        let tokens = title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let mapped = tokens.map { token -> String in
            if let n = Int(token) { return String(n) }
            if token.allSatisfy({ "ivxlcdm".contains($0) }),
               let n = RomanNumerals.parse(String(token)) {
                return String(n)
            }
            return String(token)
        }
        return mapped.joined(separator: " ")
    }

    /// Chapter bodies below this length are presumed to be table-of-contents
    /// stubs (e.g. a lone "CHAPTER I." line) rather than real chapter text.
    private static let minEligibleBodyLength = 200

    /// Aligns audio section titles to text chapter titles.
    ///
    /// - Parameters:
    ///   - sectionTitles: Titles of the audiobook's audio sections, in order.
    ///   - chapterTitles: Titles of the text chapters, in order.
    ///   - chapterBodies: Optional, parallel to `chapterTitles`. When
    ///     provided, a chapter is only eligible to be matched (exact or
    ///     containment) if its body is at least `minEligibleBodyLength`
    ///     characters — this keeps table-of-contents stubs (a lone
    ///     "CHAPTER I." line with no real body) from winning a match ahead
    ///     of the real chapter with the same title. If no chapter meets the
    ///     threshold, all chapters are treated as eligible.
    static func align(sectionTitles: [String], chapterTitles: [String], chapterBodies: [String]? = nil) -> ChapterAlignment {
        let chapters = chapterTitles.map(normalize)

        // Skip near-empty TOC stubs when matching, so a stub with the same
        // title as a real chapter doesn't win by appearing first. If nothing
        // meets the threshold (degenerate case), fall back to treating
        // everything as eligible.
        var eligible = [Bool](repeating: true, count: chapters.count)
        if let chapterBodies {
            eligible = chapterBodies.map { $0.count >= minEligibleBodyLength }
            if !eligible.contains(true) {
                eligible = [Bool](repeating: true, count: chapters.count)
            }
        }

        var result: [Int?] = []

        for sectionTitle in sectionTitles {
            let section = normalize(sectionTitle)
            if let exact = chapters.indices.first(where: { eligible[$0] && chapters[$0] == section }) {
                result.append(exact)
                continue
            }
            // Padded containment so "chapter 1" can't match inside "chapter 12".
            let padded = " \(section) "
            let contained = chapters.indices.first { i in
                guard eligible[i] else { return false }
                let chapter = chapters[i]
                guard !chapter.isEmpty else { return false }
                return padded.contains(" \(chapter) ") || " \(chapter) ".contains(padded)
            }
            result.append(contained)
        }

        if result.allSatisfy({ $0 == nil }), sectionTitles.count == chapterTitles.count {
            result = (0..<sectionTitles.count).map { $0 }
        }
        return ChapterAlignment(chapterIndexBySection: result)
    }
}
