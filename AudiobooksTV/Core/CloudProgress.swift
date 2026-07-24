import Foundation

/// One book's synced playback position (ms-epoch timestamps, matching the
/// web app's `progressMerge.ts`).
struct CloudPosition: Codable, Equatable {
    let bookTitle: String
    let coverURL: String?
    let sectionIndex: Int
    let seconds: Double
    let updatedAt: Double
}

/// Cloud form of listening progress. Positions are last-writer-wins per
/// book; finished sections are a mark/tombstone set (finished iff the
/// finished mark is newer than any unfinished mark). Merging never deletes
/// marks, so device states always converge.
struct CloudProgress: Equatable {
    var positions: [String: CloudPosition]
    var finishedMarks: [String: Double]
    var unfinishedMarks: [String: Double]
    var hiddenMarks: [String: Double]
    var unhiddenMarks: [String: Double]

    static let empty = CloudProgress(
        positions: [:], finishedMarks: [:], unfinishedMarks: [:],
        hiddenMarks: [:], unhiddenMarks: [:]
    )

    static func sectionKey(bookID: Int, sectionIndex: Int) -> String {
        "\(bookID)#\(sectionIndex)"
    }

    /// Key for the per-book hidden maps; matches the `positions` map's keys.
    static func bookKey(bookID: Int) -> String {
        String(bookID)
    }

    func isFinished(bookID: Int, sectionIndex: Int) -> Bool {
        let key = Self.sectionKey(bookID: bookID, sectionIndex: sectionIndex)
        guard let finished = finishedMarks[key] else { return false }
        guard let unfinished = unfinishedMarks[key] else { return true }
        return finished > unfinished
    }

    /// Hidden iff the hide mark is newer than any unhide mark — the same
    /// rule as finished sections, keyed by book instead of section.
    func isHidden(bookID: Int) -> Bool {
        let key = Self.bookKey(bookID: bookID)
        guard let hidden = hiddenMarks[key] else { return false }
        guard let unhidden = unhiddenMarks[key] else { return true }
        return hidden > unhidden
    }

    /// The newer of two positions by updatedAt. Exact-tie comparisons fall
    /// back to content fields so the choice is deterministic and merge
    /// order never matters (merge(a, b) == merge(b, a)) — matching the web
    /// port's newerPosition in progressMerge.ts.
    private static func newer(_ x: CloudPosition, _ y: CloudPosition) -> CloudPosition {
        if x.updatedAt != y.updatedAt { return x.updatedAt > y.updatedAt ? x : y }
        if x.seconds != y.seconds { return x.seconds > y.seconds ? x : y }
        if x.sectionIndex != y.sectionIndex { return x.sectionIndex > y.sectionIndex ? x : y }
        if x.bookTitle != y.bookTitle { return x.bookTitle > y.bookTitle ? x : y }
        return (x.coverURL ?? "") >= (y.coverURL ?? "") ? x : y
    }

    static func merge(_ a: CloudProgress, _ b: CloudProgress) -> CloudProgress {
        var positions = a.positions
        for (key, position) in b.positions {
            positions[key] = positions[key].map { newer($0, position) } ?? position
        }
        return CloudProgress(
            positions: positions,
            finishedMarks: a.finishedMarks.merging(b.finishedMarks, uniquingKeysWith: max),
            unfinishedMarks: a.unfinishedMarks.merging(b.unfinishedMarks, uniquingKeysWith: max),
            hiddenMarks: a.hiddenMarks.merging(b.hiddenMarks, uniquingKeysWith: max),
            unhiddenMarks: a.unhiddenMarks.merging(b.unhiddenMarks, uniquingKeysWith: max)
        )
    }

    // MARK: Local conversion

    /// Local store state → cloud form for the first-sign-in upload.
    /// Finished sets have no local timestamps; they upload as marks at `now`.
    static func fromLocal(
        items: [PlaybackProgress], finished: [Int: Set<Int>], hidden: Set<Int>,
        now: Date = Date()
    ) -> CloudProgress {
        var positions: [String: CloudPosition] = [:]
        for item in items {
            positions[String(item.bookID)] = CloudPosition(
                bookTitle: item.bookTitle,
                coverURL: item.coverURL?.absoluteString,
                sectionIndex: item.sectionIndex,
                seconds: item.seconds,
                updatedAt: item.updatedAt.timeIntervalSince1970 * 1000
            )
        }
        var marks: [String: Double] = [:]
        let ms = now.timeIntervalSince1970 * 1000
        for (bookID, sections) in finished {
            for section in sections {
                marks[sectionKey(bookID: bookID, sectionIndex: section)] = ms
            }
        }
        var hiddenMarks: [String: Double] = [:]
        for bookID in hidden {
            hiddenMarks[bookKey(bookID: bookID)] = ms
        }
        return CloudProgress(
            positions: positions, finishedMarks: marks, unfinishedMarks: [:],
            hiddenMarks: hiddenMarks, unhiddenMarks: [:]
        )
    }

    /// Cloud positions as the local Continue Listening list: newest first,
    /// capped at 20 (mirrors ProgressStore's cap).
    var localItems: [PlaybackProgress] {
        let all = positions.compactMap { key, value -> PlaybackProgress? in
            guard let bookID = Int(key) else { return nil }
            return PlaybackProgress(
                bookID: bookID,
                bookTitle: value.bookTitle,
                coverURL: value.coverURL.flatMap(URL.init(string:)),
                sectionIndex: value.sectionIndex,
                seconds: value.seconds,
                updatedAt: Date(timeIntervalSince1970: value.updatedAt / 1000)
            )
        }
        return Array(all.sorted { $0.updatedAt > $1.updatedAt }.prefix(20))
    }

    /// Effective finished sections (marks minus newer tombstones) keyed by book.
    var localFinished: [Int: Set<Int>] {
        var result: [Int: Set<Int>] = [:]
        for key in finishedMarks.keys {
            let parts = key.split(separator: "#")
            guard parts.count == 2,
                  let bookID = Int(parts[0]),
                  let sectionIndex = Int(parts[1]),
                  isFinished(bookID: bookID, sectionIndex: sectionIndex) else { continue }
            result[bookID, default: []].insert(sectionIndex)
        }
        return result
    }

    /// Effective hidden books (marks minus newer tombstones).
    var localHidden: Set<Int> {
        var result: Set<Int> = []
        for key in hiddenMarks.keys {
            guard let bookID = Int(key), isHidden(bookID: bookID) else { continue }
            result.insert(bookID)
        }
        return result
    }

    // MARK: Firestore payload conversion (kept Firebase-free for testability)

    static func fromDictionary(_ dict: [String: Any]) -> CloudProgress {
        var progress = CloudProgress.empty
        if let rawPositions = dict["positions"] as? [String: Any] {
            for (key, raw) in rawPositions {
                guard let fields = raw as? [String: Any],
                      let bookTitle = fields["bookTitle"] as? String,
                      let sectionIndex = fields["sectionIndex"] as? Int,
                      let seconds = fields["seconds"] as? Double ?? (fields["seconds"] as? Int).map(Double.init),
                      let updatedAt = fields["updatedAt"] as? Double ?? (fields["updatedAt"] as? Int).map(Double.init)
                else { continue }
                progress.positions[key] = CloudPosition(
                    bookTitle: bookTitle,
                    coverURL: fields["coverURL"] as? String,
                    sectionIndex: sectionIndex,
                    seconds: seconds,
                    updatedAt: updatedAt
                )
            }
        }
        progress.finishedMarks = Self.numberMap(dict["finishedMarks"])
        progress.unfinishedMarks = Self.numberMap(dict["unfinishedMarks"])
        progress.hiddenMarks = Self.numberMap(dict["hiddenMarks"])
        progress.unhiddenMarks = Self.numberMap(dict["unhiddenMarks"])
        return progress
    }

    private static func numberMap(_ raw: Any?) -> [String: Double] {
        guard let dict = raw as? [String: Any] else { return [:] }
        return dict.compactMapValues { $0 as? Double ?? ($0 as? Int).map(Double.init) }
    }

    var asDictionary: [String: Any] {
        var rawPositions: [String: Any] = [:]
        for (key, position) in positions {
            var fields: [String: Any] = [
                "bookTitle": position.bookTitle,
                "sectionIndex": position.sectionIndex,
                "seconds": position.seconds,
                "updatedAt": position.updatedAt,
            ]
            if let coverURL = position.coverURL { fields["coverURL"] = coverURL }
            rawPositions[key] = fields
        }
        return [
            "positions": rawPositions,
            "finishedMarks": finishedMarks,
            "unfinishedMarks": unfinishedMarks,
            "hiddenMarks": hiddenMarks,
            "unhiddenMarks": unhiddenMarks,
        ]
    }
}
