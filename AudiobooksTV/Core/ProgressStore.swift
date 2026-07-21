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
    private static let finishedKey = "finishedSections.v1"
    private static let cap = 20

    @Published private(set) var items: [PlaybackProgress] = []
    /// Finished section indexes per book ID. Feeds gold section titles.
    @Published private(set) var finished: [Int: Set<Int>] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([PlaybackProgress].self, from: data) {
            items = decoded
        }
        if let data = defaults.data(forKey: Self.finishedKey),
           let decoded = try? JSONDecoder().decode([Int: Set<Int>].self, from: data) {
            finished = decoded
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

    func finishedSections(bookID: Int) -> Set<Int> {
        finished[bookID] ?? []
    }

    func isFinished(bookID: Int, sectionIndex: Int) -> Bool {
        finished[bookID]?.contains(sectionIndex) ?? false
    }

    func markFinished(bookID: Int, sectionIndex: Int) {
        finished[bookID, default: []].insert(sectionIndex)
        persistFinished()
    }

    func toggleFinished(bookID: Int, sectionIndex: Int) {
        if isFinished(bookID: bookID, sectionIndex: sectionIndex) {
            finished[bookID]?.remove(sectionIndex)
            if finished[bookID]?.isEmpty == true {
                finished.removeValue(forKey: bookID)
            }
        } else {
            finished[bookID, default: []].insert(sectionIndex)
        }
        persistFinished()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private func persistFinished() {
        if let data = try? JSONEncoder().encode(finished) {
            defaults.set(data, forKey: Self.finishedKey)
        }
    }
}
