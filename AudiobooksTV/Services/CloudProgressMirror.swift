import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

/// Mirrors ProgressStore and PreambleOffsetStore to Firestore while signed
/// in. Local stores stay the UI's source of truth; remote snapshots merge
/// in via CloudProgress.merge and re-apply through applyRemote (which fires
/// no hooks, so echoes can't loop). Firestore errors never block local
/// writes; retries are the SDK's job.
@MainActor
final class CloudProgressMirror {
    static let shared = CloudProgressMirror()

    private var progressListener: ListenerRegistration?
    private var preambleListener: ListenerRegistration?
    private var lastKnown = CloudProgress.empty

    private var progressDoc: DocumentReference? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return Firestore.firestore().document("users/\(uid)/state/progress")
    }

    private var preambleDoc: DocumentReference? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        return Firestore.firestore().document("users/\(uid)/state/preambles")
    }

    func start() {
        guard FirebaseApp.app() != nil else { return }
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                if user != nil {
                    self?.attach()
                } else {
                    self?.detach()
                }
            }
        }
    }

    private func attach() {
        let store = ProgressStore.shared
        let preambles = PreambleOffsetStore.shared

        // Local changes → Firestore (field-level merges; no clobbering).
        store.onPositionSaved = { [weak self] progress in
            var cloud = CloudProgress.empty
            cloud.positions[String(progress.bookID)] = CloudPosition(
                bookTitle: progress.bookTitle,
                coverURL: progress.coverURL?.absoluteString,
                sectionIndex: progress.sectionIndex,
                seconds: progress.seconds,
                updatedAt: progress.updatedAt.timeIntervalSince1970 * 1000
            )
            self?.lastKnown = CloudProgress.merge(self?.lastKnown ?? .empty, cloud)
            self?.progressDoc?.setData(
                ["positions": cloud.asDictionary["positions"] as Any], merge: true
            )
        }
        store.onFinishedMarked = { [weak self] bookID, sectionIndex in
            self?.writeMark(field: "finishedMarks", bookID: bookID, sectionIndex: sectionIndex)
        }
        store.onFinishedUnmarked = { [weak self] bookID, sectionIndex in
            self?.writeMark(field: "unfinishedMarks", bookID: bookID, sectionIndex: sectionIndex)
        }
        preambles.onSaved = { [weak self] sectionID, offset in
            self?.preambleDoc?.setData(["offsets": [sectionID: offset]], merge: true)
        }

        // First attach: union local state into the cloud doc, then listen.
        let localCloud = CloudProgress.fromLocal(items: store.items, finished: store.finished)
        progressDoc?.setData(localCloud.asDictionary, merge: true)

        progressListener = progressDoc?.addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let data = snapshot?.data() else { return }
            Task { @MainActor in
                let remote = CloudProgress.fromDictionary(data)
                let merged = CloudProgress.merge(self.lastKnown, remote)
                guard merged != self.lastKnown else { return }
                self.lastKnown = merged
                ProgressStore.shared.applyRemote(
                    items: merged.localItems, finished: merged.localFinished
                )
            }
        }
        preambleListener = preambleDoc?.addSnapshotListener { snapshot, _ in
            guard let offsets = snapshot?.data()?["offsets"] as? [String: Any] else { return }
            let numeric = offsets.compactMapValues { $0 as? Double ?? ($0 as? Int).map(Double.init) }
            Task { @MainActor in
                PreambleOffsetStore.shared.applyRemote(offsets: numeric)
            }
        }
        lastKnown = CloudProgress.merge(lastKnown, localCloud)
    }

    private func writeMark(field: String, bookID: Int, sectionIndex: Int) {
        let key = CloudProgress.sectionKey(bookID: bookID, sectionIndex: sectionIndex)
        let now = Date().timeIntervalSince1970 * 1000
        if field == "finishedMarks" { lastKnown.finishedMarks[key] = now }
        else { lastKnown.unfinishedMarks[key] = now }
        progressDoc?.setData([field: [key: now]], merge: true)
    }

    private func detach() {
        progressListener?.remove()
        preambleListener?.remove()
        progressListener = nil
        preambleListener = nil
        lastKnown = .empty
        ProgressStore.shared.onPositionSaved = nil
        ProgressStore.shared.onFinishedMarked = nil
        ProgressStore.shared.onFinishedUnmarked = nil
        PreambleOffsetStore.shared.onSaved = nil
    }
}
