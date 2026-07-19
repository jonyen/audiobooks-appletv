import Foundation

struct BibleBook: Identifiable, Hashable {
    let name: String
    let chapters: Int
    let isOldTestament: Bool

    var id: String { name }

    static let oldTestament: [BibleBook] = [
        .init(name: "Genesis", chapters: 50, isOldTestament: true),
        .init(name: "Exodus", chapters: 40, isOldTestament: true),
        .init(name: "Leviticus", chapters: 27, isOldTestament: true),
        .init(name: "Numbers", chapters: 36, isOldTestament: true),
        .init(name: "Deuteronomy", chapters: 34, isOldTestament: true),
        .init(name: "Joshua", chapters: 24, isOldTestament: true),
        .init(name: "Judges", chapters: 21, isOldTestament: true),
        .init(name: "Ruth", chapters: 4, isOldTestament: true),
        .init(name: "1 Samuel", chapters: 31, isOldTestament: true),
        .init(name: "2 Samuel", chapters: 24, isOldTestament: true),
        .init(name: "1 Kings", chapters: 22, isOldTestament: true),
        .init(name: "2 Kings", chapters: 25, isOldTestament: true),
        .init(name: "1 Chronicles", chapters: 29, isOldTestament: true),
        .init(name: "2 Chronicles", chapters: 36, isOldTestament: true),
        .init(name: "Ezra", chapters: 10, isOldTestament: true),
        .init(name: "Nehemiah", chapters: 13, isOldTestament: true),
        .init(name: "Esther", chapters: 10, isOldTestament: true),
        .init(name: "Job", chapters: 42, isOldTestament: true),
        .init(name: "Psalms", chapters: 150, isOldTestament: true),
        .init(name: "Proverbs", chapters: 31, isOldTestament: true),
        .init(name: "Ecclesiastes", chapters: 12, isOldTestament: true),
        .init(name: "Song of Solomon", chapters: 8, isOldTestament: true),
        .init(name: "Isaiah", chapters: 66, isOldTestament: true),
        .init(name: "Jeremiah", chapters: 52, isOldTestament: true),
        .init(name: "Lamentations", chapters: 5, isOldTestament: true),
        .init(name: "Ezekiel", chapters: 48, isOldTestament: true),
        .init(name: "Daniel", chapters: 12, isOldTestament: true),
        .init(name: "Hosea", chapters: 14, isOldTestament: true),
        .init(name: "Joel", chapters: 3, isOldTestament: true),
        .init(name: "Amos", chapters: 9, isOldTestament: true),
        .init(name: "Obadiah", chapters: 1, isOldTestament: true),
        .init(name: "Jonah", chapters: 4, isOldTestament: true),
        .init(name: "Micah", chapters: 7, isOldTestament: true),
        .init(name: "Nahum", chapters: 3, isOldTestament: true),
        .init(name: "Habakkuk", chapters: 3, isOldTestament: true),
        .init(name: "Zephaniah", chapters: 3, isOldTestament: true),
        .init(name: "Haggai", chapters: 2, isOldTestament: true),
        .init(name: "Zechariah", chapters: 14, isOldTestament: true),
        .init(name: "Malachi", chapters: 4, isOldTestament: true),
    ]

    static let newTestament: [BibleBook] = [
        .init(name: "Matthew", chapters: 28, isOldTestament: false),
        .init(name: "Mark", chapters: 16, isOldTestament: false),
        .init(name: "Luke", chapters: 24, isOldTestament: false),
        .init(name: "John", chapters: 21, isOldTestament: false),
        .init(name: "Acts", chapters: 28, isOldTestament: false),
        .init(name: "Romans", chapters: 16, isOldTestament: false),
        .init(name: "1 Corinthians", chapters: 16, isOldTestament: false),
        .init(name: "2 Corinthians", chapters: 13, isOldTestament: false),
        .init(name: "Galatians", chapters: 6, isOldTestament: false),
        .init(name: "Ephesians", chapters: 6, isOldTestament: false),
        .init(name: "Philippians", chapters: 4, isOldTestament: false),
        .init(name: "Colossians", chapters: 4, isOldTestament: false),
        .init(name: "1 Thessalonians", chapters: 5, isOldTestament: false),
        .init(name: "2 Thessalonians", chapters: 3, isOldTestament: false),
        .init(name: "1 Timothy", chapters: 6, isOldTestament: false),
        .init(name: "2 Timothy", chapters: 4, isOldTestament: false),
        .init(name: "Titus", chapters: 3, isOldTestament: false),
        .init(name: "Philemon", chapters: 1, isOldTestament: false),
        .init(name: "Hebrews", chapters: 13, isOldTestament: false),
        .init(name: "James", chapters: 5, isOldTestament: false),
        .init(name: "1 Peter", chapters: 5, isOldTestament: false),
        .init(name: "2 Peter", chapters: 3, isOldTestament: false),
        .init(name: "1 John", chapters: 5, isOldTestament: false),
        .init(name: "2 John", chapters: 1, isOldTestament: false),
        .init(name: "3 John", chapters: 1, isOldTestament: false),
        .init(name: "Jude", chapters: 1, isOldTestament: false),
        .init(name: "Revelation", chapters: 22, isOldTestament: false),
    ]

    static let all: [BibleBook] = oldTestament + newTestament

    /// Reference string for a chapter, e.g. "John 3". Single-chapter books
    /// (Obadiah, Philemon, 2–3 John, Jude) are referenced by name alone.
    func reference(chapter: Int) -> String {
        chapters == 1 ? name : "\(name) \(chapter)"
    }
}
