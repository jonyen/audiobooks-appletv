import SwiftUI

struct ReaderView: View {
    let book: BibleBook

    @State private var chapter: Int
    @State private var passage: Passage?
    @State private var styledText = AttributedString()
    @State private var errorMessage: String?
    @State private var isLoadingText = false
    @State private var isLoadingAudio = false
    @State private var loadedAudioChapter: Int?
    @State private var pendingAutoplay = false
    @State private var autoAdvance = true

    @StateObject private var audio = AudioPlayerModel()

    init(book: BibleBook, chapter: Int) {
        self.book = book
        _chapter = State(initialValue: chapter)
    }

    private var reference: String { book.reference(chapter: chapter) }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
                .padding(.horizontal, 64)
                .padding(.vertical, 24)

            if audio.hasItem || isLoadingAudio {
                progressBar
                    .padding(.horizontal, 64)
                    .padding(.bottom, 16)
            }

            Divider()

            passageBody

            Divider()

            Text("Scripture quotations are from the ESV® Bible (The Holy Bible, English Standard Version®), © 2001 by Crossway. Used by permission. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 64)
                .padding(.vertical, 12)
        }
        .navigationTitle(passage?.canonical ?? reference)
        .task(id: chapter) {
            await loadChapter()
        }
        .onDisappear {
            audio.stop()
        }
    }

    // MARK: Controls

    private var controlBar: some View {
        HStack(spacing: 24) {
            Button {
                chapter -= 1
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(chapter <= 1)

            Button {
                playTapped()
            } label: {
                if isLoadingAudio {
                    ProgressView()
                } else {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                }
            }
            .disabled(isLoadingAudio || isLoadingText)

            Button {
                chapter += 1
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(chapter >= book.chapters)

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

    // MARK: Passage

    @ViewBuilder
    private var passageBody: some View {
        if isLoadingText {
            Spacer()
            ProgressView("Loading \(reference)…")
            Spacer()
        } else if let errorMessage {
            Spacer()
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)
                Button("Try Again") {
                    Task { await loadChapter() }
                }
            }
            Spacer()
        } else {
            ScrollView {
                Text(styledText)
                    .frame(maxWidth: 1200, alignment: .leading)
                    .padding(.horizontal, 64)
                    .padding(.vertical, 48)
                    .focusable()
            }
        }
    }

    // MARK: Actions

    private func loadChapter() async {
        audio.stop()
        loadedAudioChapter = nil
        isLoadingText = true
        errorMessage = nil

        do {
            let passage = try await ESVClient.shared.passage(for: reference)
            self.passage = passage
            self.styledText = Self.style(passage.text)
            isLoadingText = false
            if pendingAutoplay {
                pendingAutoplay = false
                await startAudio(autoplay: true)
            }
        } catch is CancellationError {
            isLoadingText = false
        } catch {
            isLoadingText = false
            pendingAutoplay = false
            errorMessage = error.localizedDescription
        }
    }

    private func playTapped() {
        if loadedAudioChapter == chapter, audio.hasItem {
            audio.togglePlayPause()
        } else {
            Task { await startAudio(autoplay: true) }
        }
    }

    private func startAudio(autoplay: Bool) async {
        isLoadingAudio = true
        defer { isLoadingAudio = false }
        do {
            let fileURL = try await ESVClient.shared.audioFile(for: reference)
            audio.onChapterFinished = chapterFinished
            audio.load(fileURL: fileURL, autoplay: autoplay)
            loadedAudioChapter = chapter
        } catch is CancellationError {
            // View went away; nothing to do.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func chapterFinished() {
        guard autoAdvance, chapter < book.chapters else { return }
        pendingAutoplay = true
        chapter += 1
    }

    // MARK: Text styling

    /// The ESV plain-text format marks verses as "[3]". Render the numbers as
    /// small superscript-style markers and the scripture itself in a serif face.
    private static func style(_ raw: String) -> AttributedString {
        let bodyFont = Font.system(size: 38, design: .serif)
        let verseFont = Font.system(size: 22, weight: .semibold)

        var result = AttributedString()
        var cursor = raw.startIndex

        for match in raw.matches(of: #/\[(\d+)\]\s*/#) {
            if cursor < match.range.lowerBound {
                var segment = AttributedString(String(raw[cursor..<match.range.lowerBound]))
                segment.font = bodyFont
                result += segment
            }
            var number = AttributedString(String(match.1) + " ")
            number.font = verseFont
            number.foregroundColor = .secondary
            result += number
            cursor = match.range.upperBound
        }

        if cursor < raw.endIndex {
            var segment = AttributedString(String(raw[cursor...]))
            segment.font = bodyFont
            result += segment
        }

        return result
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

#Preview {
    NavigationStack {
        ReaderView(book: BibleBook.newTestament[3], chapter: 3)
    }
}
