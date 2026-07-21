import Foundation

/// Loads a book's Gutenberg text, splits it into chapters, and aligns audio
/// sections to text chapters. One instance per opened book.
@MainActor
final class BookTextModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case unavailable(String)
        case loaded
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var chapters: [TextChapter] = []
    @Published private(set) var alignment: ChapterAlignment?

    var matchSummary: String? {
        guard case .loaded = state, let alignment else { return nil }
        return "Read-along: \(alignment.matchedCount) of \(alignment.chapterIndexBySection.count) chapters matched"
    }

    func load(book: Audiobook) async {
        guard state == .idle else { return }
        guard let ebookID = book.gutenbergID else {
            state = .unavailable("Text unavailable for this book.")
            return
        }
        state = .loading
        do {
            let text = try await GutenbergClient.shared.fullText(ebookID: ebookID)
            let chapters = ChapterSplitter.split(text)
            self.chapters = chapters
            self.alignment = SectionAligner.align(
                sectionTitles: book.sections.map(\.title),
                chapterTitles: chapters.map(\.title)
            )
            state = .loaded
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    /// The matched text chapter for an audio section, or nil when unmatched
    /// (caller falls back to the whole-book scroll).
    func chapter(forSectionIndex index: Int) -> TextChapter? {
        guard let alignment,
              index < alignment.chapterIndexBySection.count,
              let chapterIndex = alignment.chapterIndexBySection[index],
              chapterIndex < chapters.count else { return nil }
        return chapters[chapterIndex]
    }
}
