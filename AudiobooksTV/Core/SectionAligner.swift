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

    static func align(sectionTitles: [String], chapterTitles: [String]) -> ChapterAlignment {
        let chapters = chapterTitles.map(normalize)
        var result: [Int?] = []

        for sectionTitle in sectionTitles {
            let section = normalize(sectionTitle)
            if let exact = chapters.firstIndex(of: section) {
                result.append(exact)
                continue
            }
            // Padded containment so "chapter 1" can't match inside "chapter 12".
            let padded = " \(section) "
            let contained = chapters.firstIndex { chapter in
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
