import { doc, onSnapshot, setDoc } from "firebase/firestore";
import { useCallback, useEffect, useMemo, useState } from "react";
import { db } from "./firebase";
import {
  continueListening,
  emptyProgress,
  isFinished as stateIsFinished,
  mergeOffsets,
  mergeProgress,
  positionsFromSnapshot,
  sectionKey,
  type PlaybackPosition,
  type ProgressState,
} from "./progressMerge";

export interface Progress {
  /** Continue Listening list: newest-first, capped at 20. */
  list: PlaybackPosition[];
  positionFor(bookID: number): PlaybackPosition | null;
  savePosition(p: Omit<PlaybackPosition, "updatedAt">): void;
  isFinished(bookID: number, sectionIndex: number): boolean;
  markFinished(bookID: number, sectionIndex: number): void;
  toggleFinished(bookID: number, sectionIndex: number): void;
}

/**
 * Live progress for the signed-in user. Reads follow the Firestore snapshot
 * (merged with local state so a slow round-trip never hides a fresh write);
 * writes are field-level merges, so concurrent devices never clobber each
 * other's entries.
 */
export function useProgress(uid: string): Progress {
  const [state, setState] = useState<ProgressState>(emptyProgress);
  const ref = useMemo(() => doc(db, "users", uid, "state", "progress"), [uid]);

  useEffect(() => {
    setState(emptyProgress());
    return onSnapshot(ref, (snapshot) => {
      const data = (snapshot.data() ?? {}) as Partial<ProgressState>;
      const remote: ProgressState = {
        positions: positionsFromSnapshot((data as Record<string, unknown>).positions),
        finishedMarks: data.finishedMarks ?? {},
        unfinishedMarks: data.unfinishedMarks ?? {},
        hiddenMarks: data.hiddenMarks ?? {},
        unhiddenMarks: data.unhiddenMarks ?? {},
      };
      setState((local) => mergeProgress(local, remote));
    });
  }, [ref]);

  const writeMark = useCallback(
    (field: "finishedMarks" | "unfinishedMarks", key: string) => {
      const now = Date.now();
      setState((s) => ({ ...s, [field]: { ...s[field], [key]: now } }));
      void setDoc(ref, { [field]: { [key]: now } }, { merge: true });
    },
    [ref]
  );

  return useMemo<Progress>(
    () => ({
      list: continueListening(state),
      positionFor: (bookID) => state.positions[String(bookID)] ?? null,
      savePosition: (p) => {
        const position: PlaybackPosition = { ...p, updatedAt: Date.now() };
        setState((s) => ({
          ...s,
          positions: { ...s.positions, [String(p.bookID)]: position },
        }));
        void setDoc(ref, { positions: { [String(p.bookID)]: position } }, { merge: true });
      },
      isFinished: (bookID, sectionIndex) => stateIsFinished(state, bookID, sectionIndex),
      markFinished: (bookID, sectionIndex) =>
        writeMark("finishedMarks", sectionKey(bookID, sectionIndex)),
      toggleFinished: (bookID, sectionIndex) => {
        const finished = stateIsFinished(state, bookID, sectionIndex);
        writeMark(
          finished ? "unfinishedMarks" : "finishedMarks",
          sectionKey(bookID, sectionIndex)
        );
      },
    }),
    [state, ref, writeMark]
  );
}

export interface Preambles {
  /** undefined = never analyzed; 0 = analyzed, nothing to skip. */
  offset(sectionID: string): number | undefined;
  saveOffset(sectionID: string, offset: number): void;
}

/** Synced preamble offsets: whichever device analyzes first spares the rest. */
export function usePreambles(uid: string): Preambles {
  const [offsets, setOffsets] = useState<Record<string, number>>({});
  const ref = useMemo(() => doc(db, "users", uid, "state", "preambles"), [uid]);

  useEffect(() => {
    setOffsets({});
    return onSnapshot(ref, (snapshot) => {
      const remote = ((snapshot.data() ?? {}).offsets ?? {}) as Record<string, number>;
      setOffsets((local) => mergeOffsets(local, remote));
    });
  }, [ref]);

  return useMemo<Preambles>(
    () => ({
      offset: (sectionID) => offsets[sectionID],
      saveOffset: (sectionID, offset) => {
        setOffsets((local) => ({ ...local, [sectionID]: offset }));
        void setDoc(ref, { offsets: { [sectionID]: offset } }, { merge: true });
      },
    }),
    [offsets, ref]
  );
}
