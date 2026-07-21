import SwiftUI

struct SearchView: View {
    @AppStorage("readAlongOnly") private var readAlongOnly = false

    @State private var query = ""
    @State private var results: [Audiobook] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 300), spacing: 32)]

    private var visibleResults: [Audiobook] {
        readAlongOnly ? results.filter(\.hasText) : results
    }

    var body: some View {
        ScrollView {
            if isSearching {
                ProgressView("Searching…")
                    .padding(.top, 120)
            } else if let errorMessage {
                VStack(spacing: 24) {
                    Text(errorMessage)
                    Button("Try Again") { Task { await search() } }
                }
                .padding(.top, 120)
            } else {
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
                .padding(.top, 32)

                LazyVGrid(columns: columns, spacing: 48) {
                    ForEach(visibleResults) { book in
                        NavigationLink(value: book) {
                            BookCardView(book: book)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(64)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Title or author")
        .onSubmit(of: .search) {
            Task { await search() }
        }
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        do {
            results = try await LibriVoxClient.shared.search(term)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }
}
