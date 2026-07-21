import Foundation

enum GutenbergError: LocalizedError {
    case notFound
    case undecodable

    var errorDescription: String? {
        switch self {
        case .notFound: return "The book text could not be found on Project Gutenberg."
        case .undecodable: return "The book text could not be decoded."
        }
    }
}

/// Fetches plain-text ebooks from Project Gutenberg and caches them on disk,
/// with the license boilerplate already stripped.
struct GutenbergClient {
    static let shared = GutenbergClient()

    func fullText(ebookID: Int) async throws -> String {
        let cacheURL = try textCacheDirectory().appendingPathComponent("pg\(ebookID).txt")
        if let cached = try? String(contentsOf: cacheURL, encoding: .utf8) {
            return cached
        }

        let candidates = [
            "https://www.gutenberg.org/cache/epub/\(ebookID)/pg\(ebookID).txt",
            "https://www.gutenberg.org/files/\(ebookID)/\(ebookID)-0.txt",
            "https://www.gutenberg.org/files/\(ebookID)/\(ebookID).txt",
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
            guard let raw = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
                throw GutenbergError.undecodable
            }
            let text = GutenbergText.stripBoilerplate(raw)
            try? text.write(to: cacheURL, atomically: true, encoding: .utf8)
            return text
        }
        throw GutenbergError.notFound
    }

    private func textCacheDirectory() throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = caches.appendingPathComponent("GutenbergText", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
