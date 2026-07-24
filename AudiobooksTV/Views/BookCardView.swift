import SwiftUI

struct BookCardView: View {
    let book: Audiobook
    /// Only set in search results; shelves filter hidden books out entirely.
    var isHidden: Bool = false

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
            .opacity(isHidden ? 0.4 : 1)
            .overlay(alignment: .topTrailing) {
                if isHidden {
                    Image(systemName: "eye.slash.fill")
                        .font(.caption)
                        .padding(8)
                        .background(.black.opacity(0.6), in: Circle())
                        .padding(8)
                }
            }

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
