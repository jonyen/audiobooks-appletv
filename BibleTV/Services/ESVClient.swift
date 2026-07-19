import Foundation

struct Passage {
    let canonical: String
    let text: String
}

enum ESVError: LocalizedError {
    case missingAPIKey
    case requestFailed(Int)
    case emptyPassage

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No ESV API key configured. Add your free key from api.esv.org to Support/Secrets.swift."
        case .requestFailed(let code):
            return "The ESV API returned an error (HTTP \(code)). Check your API key and network connection."
        case .emptyPassage:
            return "No passage text was returned for this reference."
        }
    }
}

/// Client for Crossway's ESV API (https://api.esv.org).
/// Free for non-commercial use; requests must carry a Token authorization header.
struct ESVClient {
    static let shared = ESVClient()

    private static let session: URLSession = {
        URLSession(configuration: .default, delegate: RedirectSanitizer(), delegateQueue: nil)
    }()

    // MARK: Passage text

    func passage(for reference: String) async throws -> Passage {
        var components = URLComponents(string: "https://api.esv.org/v3/passage/text/")!
        components.queryItems = [
            .init(name: "q", value: reference),
            .init(name: "include-passage-references", value: "false"),
            .init(name: "include-first-verse-numbers", value: "true"),
            .init(name: "include-verse-numbers", value: "true"),
            .init(name: "include-footnotes", value: "false"),
            .init(name: "include-headings", value: "true"),
            .init(name: "include-short-copyright", value: "false"),
        ]

        let data = try await get(components.url!)

        struct Response: Decodable {
            let canonical: String
            let passages: [String]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let text = response.passages.first,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ESVError.emptyPassage
        }
        return Passage(
            canonical: response.canonical,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: Passage audio

    /// Returns a local file URL for the chapter's MP3, downloading it if needed.
    /// The API responds with a redirect to the audio file, which URLSession follows.
    func audioFile(for reference: String) async throws -> URL {
        let cacheURL = try audioCacheDirectory().appendingPathComponent(fileName(for: reference))
        if FileManager.default.fileExists(atPath: cacheURL.path) {
            return cacheURL
        }

        var components = URLComponents(string: "https://api.esv.org/v3/passage/audio/")!
        components.queryItems = [.init(name: "q", value: reference)]

        let data = try await get(components.url!)
        try pruneAudioCache(keeping: 7)
        try data.write(to: cacheURL)
        return cacheURL
    }

    // MARK: Internals

    private func get(_ url: URL) async throws -> Data {
        let key = Secrets.esvAPIKey
        guard !key.isEmpty else { throw ESVError.missingAPIKey }

        var request = URLRequest(url: url)
        request.setValue("Token \(key)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await Self.session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ESVError.requestFailed(http.statusCode)
        }
        return data
    }

    private func audioCacheDirectory() throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let dir = caches.appendingPathComponent("ESVAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileName(for reference: String) -> String {
        let safe = reference.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(safe) + ".mp3"
    }

    /// The ESV license allows caching only a limited amount of content, so keep
    /// just a handful of recently played chapters on disk.
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

/// The audio endpoint redirects to a signed CDN URL. Forwarding our
/// `Authorization: Token …` header to that host can break signed-URL auth,
/// so strip it when the redirect leaves api.esv.org.
private final class RedirectSanitizer: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var request = request
        if request.url?.host != "api.esv.org" {
            request.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(request)
    }
}
