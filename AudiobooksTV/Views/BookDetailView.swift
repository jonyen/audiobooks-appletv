import SwiftUI

struct BookDetailView: View {
    let book: Audiobook

    var body: some View {
        Text(book.title)
    }
}
