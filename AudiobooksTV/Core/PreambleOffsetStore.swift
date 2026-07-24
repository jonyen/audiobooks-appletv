import Foundation

/// Caches detected preamble offsets per audio section so silence analysis
/// runs at most once per section. A stored 0 means "analyzed, nothing to
/// skip"; a missing key means "never analyzed".
final class PreambleOffsetStore {
    static let shared = PreambleOffsetStore()
    private static let key = "preambleOffsets.v1"

    private var offsets: [String: Double]
    private let defaults: UserDefaults

    /// Cloud-mirror hook: fired for locally-detected offsets only.
    var onSaved: ((String, Double) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        offsets = (defaults.dictionary(forKey: Self.key) as? [String: Double]) ?? [:]
    }

    func offset(sectionID: String) -> Double? {
        offsets[sectionID]
    }

    /// All cached offsets, for the cloud mirror's first-sign-in upload.
    var allOffsets: [String: Double] { offsets }

    func save(offset: Double, sectionID: String) {
        offsets[sectionID] = offset
        defaults.set(offsets, forKey: Self.key)
        onSaved?(sectionID, offset)
    }

    /// Merges remote offsets in. Existing local values win (offsets are
    /// facts about the audio; concurrent values are equivalent). No hook.
    func applyRemote(offsets remote: [String: Double]) {
        offsets = remote.merging(offsets) { _, local in local }
        defaults.set(offsets, forKey: Self.key)
    }
}
