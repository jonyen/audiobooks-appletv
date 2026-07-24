import SwiftUI

struct ShelfRowView: View {
    let shelf: Shelf
    let readAlongOnly: Bool

    @State private var books: [Audiobook] = []
    @State private var failed = false
    @ObservedObject private var progressStore = ProgressStore.shared

    private var visibleBooks: [Audiobook] {
        books.filter { book in
            !progressStore.isHidden(bookID: book.id) && (!readAlongOnly || book.hasText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(shelf.title)
                .font(.title3.bold())
                .padding(.leading, 64)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    if books.isEmpty && !failed {
                        ProgressView()
                            .frame(height: 280)
                    }
                    if failed && books.isEmpty {
                        Text("Couldn't load this shelf.")
                            .foregroundStyle(.secondary)
                            .frame(height: 280)
                    }
                    ForEach(visibleBooks) { book in
                        NavigationLink(value: book) {
                            BookCardView(book: book)
                        }
                        .buttonStyle(.card)
                        .contextMenu {
                            Button {
                                progressStore.toggleHidden(bookID: book.id)
                            } label: {
                                Label("Hide", systemImage: "eye.slash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 24)
            }
        }
        .task {
            guard books.isEmpty else { return }
            do {
                books = try await LibriVoxClient.shared.books(genre: shelf.id)
                failed = false
            } catch {
                failed = true
            }
        }
    }
}
