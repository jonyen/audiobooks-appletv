import SwiftUI

/// Read-along player: chapter text on screen, audio narrating, auto-advance.
struct PlayerView: View {
    let book: Audiobook
    @ObservedObject var textModel: BookTextModel
    let startSectionIndex: Int
    let startSeconds: Double

    @Environment(\.dismiss) private var dismiss
    @StateObject private var audio = AudioPlayerModel()

    @State private var sectionIndex: Int
    @State private var isLoadingAudio = false
    @State private var errorMessage: String?
    @State private var autoAdvance = true
    @State private var pendingSeekSeconds: Double
    @State private var lastSavedSeconds: Double = 0

    init(book: Audiobook, textModel: BookTextModel, startSectionIndex: Int, startSeconds: Double) {
        self.book = book
        self.textModel = textModel
        self.startSectionIndex = startSectionIndex
        self.startSeconds = startSeconds
        _sectionIndex = State(initialValue: startSectionIndex)
        _pendingSeekSeconds = State(initialValue: startSeconds)
    }

    private var section: AudioSection { book.sections[sectionIndex] }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
                .padding(.horizontal, 64)
                .padding(.vertical, 24)

            progressBar
                .padding(.horizontal, 64)
                .padding(.bottom, 16)

            Divider()

            textBody

        }
        .navigationTitle(section.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
        .task(id: sectionIndex) {
            await startAudio()
        }
        .onChange(of: audio.currentTime) { _, newTime in
            if abs(newTime - lastSavedSeconds) > 15 {
                saveProgress(seconds: newTime)
            }
        }
        .onDisappear {
            saveProgress(seconds: audio.currentTime)
            audio.stop()
        }
    }

    // MARK: Controls

    private var controlBar: some View {
        HStack(spacing: 24) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
            }

            Button {
                sectionIndex -= 1
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .disabled(sectionIndex <= 0)

            Button {
                audio.togglePlayPause()
                if !audio.isPlaying {
                    saveProgress(seconds: audio.currentTime)
                }
            } label: {
                if isLoadingAudio {
                    ProgressView()
                } else {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                }
            }
            .disabled(isLoadingAudio)

            Button {
                sectionIndex += 1
            } label: {
                Image(systemName: "forward.end.fill")
            }
            .disabled(sectionIndex >= book.sections.count - 1)

            Spacer()

            Text(book.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                audio.cycleRate()
            } label: {
                Text(String(format: "%g×", audio.rate))
                    .monospacedDigit()
            }

            Button {
                autoAdvance.toggle()
            } label: {
                Label("Auto-advance", systemImage: autoAdvance ? "text.line.first.and.arrowtriangle.forward" : "stop.circle")
                    .labelStyle(.iconOnly)
            }
            .foregroundStyle(autoAdvance ? .primary : .tertiary)
        }
        .font(.title3)
    }

    private var progressBar: some View {
        HStack(spacing: 16) {
            Text(timeString(audio.currentTime))
            ProgressView(value: min(audio.currentTime, audio.duration), total: max(audio.duration, 1))
            Text(timeString(audio.duration))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    // MARK: Text

    @ViewBuilder
    private var textBody: some View {
        if let errorMessage {
            Spacer()
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                Button("Try Again") {
                    self.errorMessage = nil
                    Task { await startAudio() }
                }
            }
            Spacer()
        } else if let chapter = textModel.chapter(forSectionIndex: sectionIndex) {
            chapterScroll([chapter], header: nil)
        } else if case .loaded = textModel.state {
            // Section didn't align — whole-book fallback.
            chapterScroll(textModel.chapters, header: "This chapter couldn't be matched — showing the full book text.")
        } else {
            // No text at all: cover-only player.
            Spacer()
            VStack(spacing: 24) {
                AsyncImage(url: book.coverURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fit)
                    default:
                        Image(systemName: "book.closed").font(.system(size: 120))
                    }
                }
                .frame(maxHeight: 500)
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Text("Text unavailable for this book")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func chapterScroll(_ chapters: [TextChapter], header: String?) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 32) {
                if let header {
                    Text(header)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(chapters.enumerated()), id: \.offset) { _, chapter in
                    if chapters.count > 1 {
                        Text(chapter.title)
                            .font(.system(size: 30, weight: .semibold, design: .serif))
                    }
                    Text(chapter.body)
                        .font(.system(size: 38, design: .serif))
                        .focusable()
                }
            }
            .frame(maxWidth: 1200, alignment: .leading)
            .padding(.horizontal, 64)
            .padding(.vertical, 48)
        }
    }

    // MARK: Actions

    private func startAudio() async {
        isLoadingAudio = true
        defer { isLoadingAudio = false }
        do {
            let fileURL = try await LibriVoxClient.shared.audioFile(for: section)
            audio.onChapterFinished = sectionFinished
            audio.load(fileURL: fileURL, autoplay: true)
            if pendingSeekSeconds > 0 {
                audio.seek(to: pendingSeekSeconds)
                pendingSeekSeconds = 0
            }
            saveProgress(seconds: audio.currentTime)
        } catch is CancellationError {
            // View went away; nothing to do.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sectionFinished() {
        guard autoAdvance, sectionIndex < book.sections.count - 1 else { return }
        sectionIndex += 1
    }

    private func saveProgress(seconds: Double) {
        lastSavedSeconds = seconds
        ProgressStore.shared.save(PlaybackProgress(
            bookID: book.id,
            bookTitle: book.title,
            coverURL: book.coverURL,
            sectionIndex: sectionIndex,
            seconds: seconds,
            updatedAt: Date()
        ))
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
