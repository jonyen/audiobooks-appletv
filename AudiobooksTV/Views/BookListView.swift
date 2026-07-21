import SwiftUI

struct BookListView: View {
    var body: some View {
        List {
            Section("Old Testament") {
                ForEach(BibleBook.oldTestament) { book in
                    bookRow(book)
                }
            }
            Section("New Testament") {
                ForEach(BibleBook.newTestament) { book in
                    bookRow(book)
                }
            }
        }
        .navigationTitle("Holy Bible · ESV")
        .navigationDestination(for: BibleBook.self) { book in
            if book.chapters == 1 {
                ReaderView(book: book, chapter: 1)
            } else {
                ChapterGridView(book: book)
            }
        }
    }

    private func bookRow(_ book: BibleBook) -> some View {
        NavigationLink(value: book) {
            HStack {
                Text(book.name)
                Spacer()
                Text(book.chapters == 1 ? "1 chapter" : "\(book.chapters) chapters")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}

#Preview {
    NavigationStack {
        BookListView()
    }
}
