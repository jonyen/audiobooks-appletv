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

    @State private var paragraphs: [String] = []
    @State private var timeline: ParagraphTimeline?
    @State private var currentParagraphIndex: Int?
    @FocusState private var focusedParagraph: Int?
    @State private var followSuspendedUntil = Date.distantPast
    @State private var suppressFocusSuspension = false
    @State private var controlsRevealed = false
    @State private var scrollPositionID: Int?

    @ObservedObject private var progressStore = ProgressStore.shared

    /// Controls stay visible while paused; during playback they collapse
    /// away entirely and only an explicit up-press at the top of the text
    /// reveals them. Loss of focus alone must NOT reveal them — auto-scroll
    /// can push the focused paragraph off-screen, which resets focus to nil
    /// without any user intent.
    private var controlsVisible: Bool {
        !audio.isPlaying || controlsRevealed
    }

    /// Top padding of the read-along content.
    private static let contentTopInset: CGFloat = 48

    init(book: Audiobook, textModel: BookTextModel, startSectionIndex: Int, startSeconds: Double) {
        self.book = book
        self.textModel = textModel
        self.startSectionIndex = startSectionIndex
        self.startSeconds = startSeconds
        _sectionIndex = State(initialValue: min(max(0, startSectionIndex), max(0, book.sections.count - 1)))
        _pendingSeekSeconds = State(initialValue: startSeconds)
    }

    private var section: AudioSection { book.sections[sectionIndex] }

    var body: some View {
        VStack(spacing: 0) {
            if controlsVisible {
                controlBar
                    .padding(.horizontal, 64)
                    .padding(.vertical, 24)

                progressBar
                    .padding(.horizontal, 64)
                    .padding(.bottom, 16)
            }

            Divider()

            textBody

        }
        .animation(.easeInOut(duration: 0.25), value: controlsVisible)
        .onPlayPauseCommand {
            audio.togglePlayPause()
            if !audio.isPlaying {
                saveProgress(seconds: audio.currentTime)
            }
        }
        .onMoveCommand { direction in
            // Fires only when the focus engine has no target in that
            // direction — i.e. pressing up at the top of the text while the
            // controls are collapsed. Reveal them.
            if direction == .up {
                controlsRevealed = true
            }
        }
        .navigationTitle(section.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.09, green: 0.09, blue: 0.11))
        .task(id: sectionIndex) {
            updateParagraphs()
            await startAudio()
        }
        .onReceive(textModel.$chapters) { _ in
            updateParagraphs()
        }
        .onChange(of: audio.duration) {
            rebuildTimeline()
        }
        .onChange(of: audio.currentTime) { _, newTime in
            currentParagraphIndex = timeline?.paragraphIndex(at: newTime)
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

            Button {
                ProgressStore.shared.toggleFinished(bookID: book.id, sectionIndex: sectionIndex)
            } label: {
                let isFinished = progressStore.isFinished(bookID: book.id, sectionIndex: sectionIndex)
                Label(
                    isFinished ? "Mark as Unfinished" : "Mark as Finished",
                    systemImage: isFinished ? "checkmark.circle.fill" : "checkmark.circle"
                )
                .labelStyle(.iconOnly)
            }
            .foregroundStyle(
                progressStore.isFinished(bookID: book.id, sectionIndex: sectionIndex)
                    ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary)
            )
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
        } else if textModel.chapter(forSectionIndex: sectionIndex) != nil {
            paragraphScroll
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

    private var paragraphScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    // While playback runs the chapter dims as a whole and only
                    // the narrated paragraph renders at full brightness.
                    let dimmed = audio.isPlaying && index != currentParagraphIndex
                    Text(paragraph)
                        .font(.system(size: 38, design: .serif))
                        .foregroundStyle(dimmed ? Color.secondary : Color.primary)
                        .focusable()
                        .focused($focusedParagraph, equals: index)
                        .id(index)
                }
            }
            .frame(maxWidth: 1200, alignment: .leading)
            .padding(.horizontal, 64)
            .padding(.top, Self.contentTopInset)
            // Generous bottom inset so the last lines can scroll clear of the
            // fold instead of being cut off.
            .padding(.bottom, 160)
        }
        .scrollPosition(id: $scrollPositionID, anchor: .top)
        .onChange(of: focusedParagraph) {
            // Focus settling back into the text re-collapses controls that
            // were revealed with an up-press.
            if focusedParagraph != nil {
                controlsRevealed = false
            }
            // A user-driven focus move between paragraphs is a manual scroll:
            // pause following. Exempt are programmatic moves (play-start
            // handoff) and focus dropping to nil, which auto-scroll causes by
            // pushing the focused paragraph off-screen.
            if suppressFocusSuspension {
                suppressFocusSuspension = false
            } else if audio.isPlaying, focusedParagraph != nil {
                followSuspendedUntil = Date().addingTimeInterval(10)
            }
        }
        .onChange(of: currentParagraphIndex) {
            scrollToNarratedParagraph()
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
        audio.pause()
        errorMessage = nil
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
            if !paragraphs.isEmpty {
                suppressFocusSuspension = true
                focusedParagraph = 0
            }
        } catch is CancellationError {
            // View went away or section changed; nothing to do.
        } catch let error as URLError where error.code == .cancelled {
            // Same: the in-flight download was cancelled by a newer task.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sectionFinished() {
        ProgressStore.shared.markFinished(bookID: book.id, sectionIndex: sectionIndex)
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

    /// Re-derives paragraphs when the section or the loaded text changes,
    /// resetting all sync state.
    private func updateParagraphs() {
        if let chapter = textModel.chapter(forSectionIndex: sectionIndex) {
            paragraphs = ParagraphTimeline.paragraphs(from: chapter.body)
        } else {
            paragraphs = []
        }
        currentParagraphIndex = nil
        followSuspendedUntil = .distantPast
        scrollPositionID = nil
        rebuildTimeline()
        // Text can finish loading after audio has already started (e.g. the
        // Gutenberg fetch was still in flight): hand focus to the text now
        // so highlighting starts from a clean focus state, same as the
        // handoff in startAudio().
        if audio.isPlaying, focusedParagraph == nil, !paragraphs.isEmpty {
            suppressFocusSuspension = true
            focusedParagraph = 0
        }
    }

    private func rebuildTimeline() {
        timeline = ParagraphTimeline(paragraphs: paragraphs, duration: audio.duration)
        currentParagraphIndex = timeline?.paragraphIndex(at: audio.currentTime)
    }

    /// Scrolls the narrated paragraph to the top of the frame unless the
    /// user recently moved focus manually.
    private func scrollToNarratedParagraph() {
        guard audio.isPlaying,
              Date() >= followSuspendedUntil,
              let index = currentParagraphIndex else { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            scrollPositionID = index
        }
    }
}
