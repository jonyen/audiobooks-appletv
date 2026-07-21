import SwiftUI

struct BookCardView: View {
    let book: Audiobook

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: book.coverURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "book.closed")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 280, height: 280)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(book.title)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(book.hasText ? .primary : .secondary)

            Text(book.authors)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 280)
    }
}
