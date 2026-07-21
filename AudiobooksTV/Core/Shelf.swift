import Foundation

struct Shelf: Identifiable, Hashable {
    let id: String
    let title: String

    /// Hardcoded home-screen shelves. `id` is the LibriVox genre name used in
    /// the API query; `title` is what the user sees.
    static let all: [Shelf] = [
        Shelf(id: "General Fiction", title: "Fiction"),
        Shelf(id: "Detective Fiction", title: "Mystery"),
        Shelf(id: "Science Fiction", title: "Sci-Fi"),
        Shelf(id: "Children's Fiction", title: "Children's"),
        Shelf(id: "History", title: "History"),
        Shelf(id: "Action & Adventure", title: "Adventure"),
        Shelf(id: "Poetry", title: "Poetry"),
    ]
}
