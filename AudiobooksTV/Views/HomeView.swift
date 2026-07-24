import SwiftUI

struct HomeView: View {
    @AppStorage("readAlongOnly") private var readAlongOnly = false
    @ObservedObject private var progressStore = ProgressStore.shared
    @State private var showAccount = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button {
                        readAlongOnly.toggle()
                    } label: {
                        Label("Read-along only",
                              systemImage: readAlongOnly ? "checkmark.circle.fill" : "circle")
                    }
                    .font(.caption)
                    Spacer()
                }
                .padding(.horizontal, 64)

                if !progressStore.items.isEmpty {
                    continueListeningRow
                }
                ForEach(Shelf.all) { shelf in
                    ShelfRowView(shelf: shelf, readAlongOnly: readAlongOnly)
                }
            }
            .padding(.vertical, 32)
        }
        .navigationTitle("Audiobooks")
        .navigationDestination(for: Audiobook.self) { book in
            BookDetailView(book: book)
        }
        .navigationDestination(for: PlaybackProgress.self) { progress in
            BookByIDView(bookID: progress.bookID)
        }
        .toolbar {
            ToolbarItemGroup {
                NavigationLink {
                    SearchView()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                Button {
                    showAccount = true
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
        .sheet(isPresented: $showAccount) {
            AccountView()
        }
    }

    private var continueListeningRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Continue Listening")
                .font(.title3.bold())
                .padding(.leading, 64)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    ForEach(progressStore.items, id: \.bookID) { progress in
                        NavigationLink(value: progress) {
                            VStack(alignment: .leading, spacing: 8) {
                                AsyncImage(url: progress.coverURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    default:
                                        Rectangle().fill(.quaternary)
                                    }
                                }
                                .frame(width: 280, height: 280)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 12))

                                Text(progress.bookTitle)
                                    .font(.caption)
                                    .lineLimit(2)
                            }
                            .frame(width: 280)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 64)
                .padding(.vertical, 24)
            }
        }
    }
}

/// Fetches a book by LibriVox id, then shows its detail view.
/// Used by Continue Listening, which only persists the id.
struct BookByIDView: View {
    let bookID: Int

    @State private var book: Audiobook?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let book {
                BookDetailView(book: book)
            } else if let errorMessage {
                VStack(spacing: 24) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text(errorMessage)
                    Button("Try Again") {
                        self.errorMessage = nil
                        Task { await load() }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            if let fetched = try await LibriVoxClient.shared.book(id: bookID) {
                book = fetched
            } else {
                errorMessage = "This book is no longer available."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
