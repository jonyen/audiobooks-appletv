import Foundation

enum LibriVoxError: LocalizedError {
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let code):
            return "LibriVox returned an error (HTTP \(code)). Check your network connection and try again."
        }
    }
}

/// Client for the LibriVox catalog API (https://librivox.org/api/feed/audiobooks).
/// Open API, no key. All audio files are hosted on archive.org.
actor LibriVoxClient {
    static let shared = LibriVoxClient()

    private var genreCache: [String: [Audiobook]] = [:]

    // MARK: Catalog

    func books(genre: String, limit: Int = 20) async throws -> [Audiobook] {
        if let cached = genreCache[genre] {
            return cached
        }
        let books = try await fetchBooks(queryItems: [
            .init(name: "genre", value: genre),
            .init(name: "limit", value: String(limit)),
        ])
        genreCache[genre] = books
        return books
    }

    func search(_ term: String) async throws -> [Audiobook] {
        async let byTitle = fetchBooks(queryItems: [.init(name: "title", value: term)])
        async let byAuthor = fetchBooks(queryItems: [.init(name: "author", value: term)])
        let (titles, authors) = try await (byTitle, byAuthor)

        var seen = Set<Int>()
        return (titles + authors).filter { seen.insert($0.id).inserted }
    }

    func book(id: Int) async throws -> Audiobook? {
        try await fetchBooks(queryItems: [.init(name: "id", value: String(id))]).first
    }

    private func fetchBooks(queryItems: [URLQueryItem]) async throws -> [Audiobook] {
        var components = URLComponents(string: "https://librivox.org/api/feed/audiobooks")!
        components.queryItems = queryItems + [
            .init(name: "format", value: "json"),
            .init(name: "extended", value: "1"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw LibriVoxError.requestFailed(http.statusCode)
        }
        return try LibriVoxParser.parseBooks(data)
    }

    // MARK: Audio download + cache

    /// Returns a local file URL for the section's MP3, downloading if needed.
    /// Keeps the 20 most recently played sections on disk.
    func audioFile(for section: AudioSection) async throws -> URL {
        let cacheURL = try audioCacheDirectory().appendingPathComponent("section-\(section.id).mp3")
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        let (data, response) = try await URLSession.shared.data(from: section.listenURL)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw LibriVoxError.requestFailed(http.statusCode)
        }
        try pruneAudioCache(keeping: 20)
        try data.write(to: cacheURL)
        return cacheURL
    }

    private func audioCacheDirectory() throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = caches.appendingPathComponent("LibriVoxAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func pruneAudioCache(keeping limit: Int) throws {
        let fm = FileManager.default
        let dir = try audioCacheDirectory()
        let files = try fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        )
        guard files.count >= limit else { return }

        let sorted = files.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
        for file in sorted.prefix(files.count - limit + 1) {
            try? fm.removeItem(at: file)
        }
    }
}
