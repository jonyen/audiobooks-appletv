import Foundation

struct Audiobook: Identifiable, Hashable {
    let id: Int
    let title: String
    let authors: String
    let description: String
    let genres: [String]
    let coverURL: URL?
    let textSourceURL: String?
    let totalTimeSeconds: Int
    let sections: [AudioSection]

    var gutenbergID: Int? {
        textSourceURL.flatMap(GutenbergText.ebookID(fromTextSource:))
    }

    var hasText: Bool { gutenbergID != nil }
}

struct AudioSection: Identifiable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let listenURL: URL
    let playtimeSeconds: Int
}
