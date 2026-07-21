import SwiftUI

struct ShelfRowView: View {
    let shelf: Shelf
    let readAlongOnly: Bool

    @State private var books: [Audiobook] = []
    @State private var failed = false

    private var visibleBooks: [Audiobook] {
        readAlongOnly ? books.filter(\.hasText) : books
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
                    if failed {
                        Text("Couldn't load this shelf.")
                            .foregroundStyle(.secondary)
                            .frame(height: 280)
                    }
                    ForEach(visibleBooks) { book in
                        NavigationLink(value: book) {
                            BookCardView(book: book)
                        }
                        .buttonStyle(.card)
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
            } catch {
                failed = true
            }
        }
    }
}
