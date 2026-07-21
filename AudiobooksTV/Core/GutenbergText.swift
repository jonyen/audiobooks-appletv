import Foundation

enum GutenbergText {
    /// Extracts the Project Gutenberg ebook ID from a LibriVox `url_text_source`
    /// value. Returns nil when the source is not a gutenberg.org URL.
    static func ebookID(fromTextSource url: String) -> Int? {
        guard url.contains("gutenberg.org") else { return nil }
        let patterns = [
            #/\/etext\/(\d+)/#,
            #/\/ebooks\/(\d+)/#,
            #/\/files\/(\d+)/#,
            #/\/epub\/(\d+)/#,
        ]
        for pattern in patterns {
            if let match = url.firstMatch(of: pattern) {
                return Int(match.1)
            }
        }
        return nil
    }

    /// Removes the Project Gutenberg license header and footer, keeping only
    /// the book body. Texts without markers are returned trimmed but intact.
    static func stripBoilerplate(_ raw: String) -> String {
        // CRLF endings break the [^\n]* marker patterns (a \r\n grapheme
        // straddles the match boundary), so normalize before matching.
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        if let start = text.range(
            of: #"\*\*\* ?START OF TH(E|IS) PROJECT GUTENBERG EBOOK[^\n]*"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            text = String(text[start.upperBound...])
        }
        if let end = text.range(
            of: #"\*\*\* ?END OF TH(E|IS) PROJECT GUTENBERG EBOOK"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            text = String(text[..<end.lowerBound])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
