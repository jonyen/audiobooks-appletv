import Foundation
import Combine

struct PlaybackProgress: Codable, Equatable, Hashable {
    let bookID: Int
    let bookTitle: String
    let coverURL: URL?
    let sectionIndex: Int
    let seconds: Double
    let updatedAt: Date
}

/// Persists per-book playback positions in UserDefaults.
/// Newest-first, capped at 20 books. Feeds the "Continue Listening" shelf.
final class ProgressStore: ObservableObject {
    static let shared = ProgressStore()
    private static let key = "playbackProgress.v1"
    private static let cap = 20

    @Published private(set) var items: [PlaybackProgress] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([PlaybackProgress].self, from: data) {
            items = decoded
        }
    }

    func save(_ progress: PlaybackProgress) {
        items.removeAll { $0.bookID == progress.bookID }
        items.insert(progress, at: 0)
        if items.count > Self.cap {
            items.removeLast(items.count - Self.cap)
        }
        persist()
    }

    func progress(for bookID: Int) -> PlaybackProgress? {
        items.first { $0.bookID == bookID }
    }

    func remove(bookID: Int) {
        items.removeAll { $0.bookID == bookID }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
