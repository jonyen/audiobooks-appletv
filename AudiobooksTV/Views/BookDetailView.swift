import SwiftUI

struct BookDetailView: View {
    let book: Audiobook

    @StateObject private var textModel = BookTextModel()
    @State private var playTarget: PlayTarget?

    private struct PlayTarget: Identifiable, Hashable {
        let id = UUID()
        let sectionIndex: Int
        let seconds: Double
    }

    private var savedProgress: PlaybackProgress? {
        ProgressStore.shared.progress(for: book.id)
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 48) {
                AsyncImage(url: book.coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Rectangle().fill(.quaternary)
                    }
                }
                .frame(width: 400, height: 400)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 16) {
                    Text(book.title).font(.title2.bold())
                    Text(book.authors).font(.title3).foregroundStyle(.secondary)

                    switch textModel.state {
                    case .loading, .idle:
                        Label("Checking read-along text…", systemImage: "text.book.closed")
                            .foregroundStyle(.secondary)
                    case .loaded:
                        Label(textModel.matchSummary ?? "Read-along available",
                              systemImage: "text.book.closed.fill")
                    case .unavailable:
                        Label("Text unavailable — audio only", systemImage: "headphones")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        if let saved = savedProgress {
                            playTarget = PlayTarget(sectionIndex: saved.sectionIndex, seconds: saved.seconds)
                        } else {
                            playTarget = PlayTarget(sectionIndex: 0, seconds: 0)
                        }
                    } label: {
                        Label(savedProgress == nil ? "Play" : "Resume",
                              systemImage: "play.fill")
                    }
                    .disabled(book.sections.isEmpty)

                    if !book.description.isEmpty {
                        Text(book.description)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                    }
                }
                Spacer()
            }
            .padding(64)

            VStack(alignment: .leading, spacing: 8) {
                Text("Chapters").font(.title3.bold())
                ForEach(Array(book.sections.enumerated()), id: \.element.id) { index, section in
                    Button {
                        playTarget = PlayTarget(sectionIndex: index, seconds: 0)
                    } label: {
                        HStack {
                            Text(section.title)
                            Spacer()
                            Text(timeString(section.playtimeSeconds))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .padding(.horizontal, 64)
            .padding(.bottom, 48)
        }
        .navigationTitle(book.title)
        .task {
            await textModel.load(book: book)
        }
        .fullScreenCover(item: $playTarget) { target in
            PlayerView(
                book: book,
                textModel: textModel,
                startSectionIndex: target.sectionIndex,
                startSeconds: target.seconds
            )
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
