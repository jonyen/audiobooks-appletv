import SwiftUI

struct ChapterGridView: View {
    let book: BibleBook

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 32)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 32) {
                ForEach(1...book.chapters, id: \.self) { chapter in
                    NavigationLink {
                        ReaderView(book: book, chapter: chapter)
                    } label: {
                        Text("\(chapter)")
                            .font(.title2)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(48)
        }
        .navigationTitle(book.name)
    }
}

#Preview {
    NavigationStack {
        ChapterGridView(book: BibleBook.newTestament[3])
    }
}
