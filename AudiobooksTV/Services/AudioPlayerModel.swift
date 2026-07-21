import AVFoundation
import Combine

@MainActor
final class AudioPlayerModel: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var rate: Float = 1.0

    /// Called when the loaded chapter finishes playing to the end.
    var onChapterFinished: (() -> Void)?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var finishObserver: NSObjectProtocol?

    private static let rates: [Float] = [1.0, 1.25, 1.5, 0.75]

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func load(fileURL: URL, autoplay: Bool) {
        stop()

        let item = AVPlayerItem(url: fileURL)
        let player = AVPlayer(playerItem: item)
        self.player = player

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time.seconds
                if let duration = self.player?.currentItem?.duration.seconds, duration.isFinite {
                    self.duration = duration
                }
            }
        }

        finishObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = false
                self.currentTime = self.duration
                self.onChapterFinished?()
            }
        }

        if autoplay {
            play()
        }
    }

    var hasItem: Bool { player?.currentItem != nil }

    func play() {
        guard let player else { return }
        // Restart from the top if the chapter already played to the end.
        if duration > 0, currentTime >= duration - 0.5 {
            player.seek(to: .zero)
        }
        player.rate = rate
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func skip(by seconds: Double) {
        guard let player else { return }
        let target = max(0, min(currentTime + seconds, duration))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    /// Absolute seek for restoring a saved position. Unlike skip(by:), this
    /// does not clamp to `duration`, which is still 0 right after load —
    /// AVPlayer queues the seek and applies it once the item is ready.
    func seek(to seconds: Double) {
        guard let player, seconds > 0 else { return }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func cycleRate() {
        let index = Self.rates.firstIndex(of: rate) ?? 0
        rate = Self.rates[(index + 1) % Self.rates.count]
        if isPlaying {
            player?.rate = rate
        }
    }

    func stop() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        if let finishObserver {
            NotificationCenter.default.removeObserver(finishObserver)
        }
        timeObserver = nil
        finishObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }
}
