import Foundation

enum LibriVoxParser {
    struct Envelope: Decodable {
        let books: [BookDTO]?
        let error: String?
    }

    struct BookDTO: Decodable {
        let id: String
        let title: String?
        let description: String?
        let url_text_source: String?
        let url_iarchive: String?
        let coverart_jpg: String?
        let totaltimesecs: Int?
        let authors: [AuthorDTO]?
        let genres: [GenreDTO]?
        let sections: [SectionDTO]?
    }

    struct AuthorDTO: Decodable {
        let first_name: String?
        let last_name: String?
    }

    struct GenreDTO: Decodable {
        let name: String?
    }

    struct SectionDTO: Decodable {
        let id: String
        let section_number: String?
        let title: String?
        let listen_url: String?
        let playtime: String?
    }

    static func parseBooks(_ data: Data) throws -> [Audiobook] {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let dtos = envelope.books else { return [] }
        return dtos.compactMap(makeBook)
    }

    private static func makeBook(_ dto: BookDTO) -> Audiobook? {
        guard let id = Int(dto.id) else { return nil }

        let authorNames = (dto.authors ?? []).map { author in
            [author.first_name, author.last_name]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }.filter { !$0.isEmpty }

        let sections = (dto.sections ?? []).compactMap { section -> AudioSection? in
            guard let sectionID = Int(section.id),
                  let urlString = section.listen_url,
                  let url = URL(string: urlString) else { return nil }
            return AudioSection(
                id: sectionID,
                number: section.section_number.flatMap(Int.init) ?? 0,
                title: section.title ?? "Section",
                listenURL: url,
                playtimeSeconds: section.playtime.flatMap(Int.init) ?? 0
            )
        }

        return Audiobook(
            id: id,
            title: dto.title ?? "Untitled",
            authors: authorNames.joined(separator: ", "),
            description: stripHTML(dto.description ?? ""),
            genres: (dto.genres ?? []).compactMap(\.name),
            coverURL: coverURL(coverart: dto.coverart_jpg, iarchive: dto.url_iarchive),
            textSourceURL: dto.url_text_source?.isEmpty == false ? dto.url_text_source : nil,
            totalTimeSeconds: dto.totaltimesecs ?? 0,
            sections: sections
        )
    }

    private static func coverURL(coverart: String?, iarchive: String?) -> URL? {
        if let coverart, !coverart.isEmpty, let url = URL(string: coverart) {
            return url
        }
        if let iarchive,
           let identifier = URL(string: iarchive)?.lastPathComponent,
           !identifier.isEmpty {
            return URL(string: "https://archive.org/services/img/\(identifier)")
        }
        return nil
    }

    static func stripHTML(_ s: String) -> String {
        s.replacing(#/<[^>]+>/#, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
