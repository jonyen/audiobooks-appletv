import XCTest
@testable import AudiobooksCore

final class PreambleDetectorTests: XCTestCase {

    /// Builds an RMS array from (level, seconds) segments at 0.1s windows.
    private func windows(_ segments: [(level: Float, seconds: Double)]) -> [Float] {
        segments.flatMap { Array(repeating: $0.level, count: Int($0.seconds * 10)) }
    }

    func testPicksLongestQualifyingSilence() {
        // 10s speech, 1s pause, 9s speech, 2s pause (ends at 22s), 10s speech.
        let rms = windows([(1.0, 10), (0.0, 1), (1.0, 9), (0.0, 2), (1.0, 10)])
        XCTAssertEqual(PreambleDetector.preambleEnd(windowRMS: rms, windowDuration: 0.1)!,
                       22.0, accuracy: 0.11)
    }

    func testIgnoresSilenceEndingBeforeMinEnd() {
        // Only pause ends at 4s — inside the credits, not after them.
        let rms = windows([(1.0, 2), (0.0, 2), (1.0, 26)])
        XCTAssertNil(PreambleDetector.preambleEnd(windowRMS: rms, windowDuration: 0.1))
    }

    func testIgnoresShortSilences() {
        // Pauses of 0.5s never qualify (minSilence 0.8).
        let rms = windows([(1.0, 10), (0.0, 0.5), (1.0, 10), (0.0, 0.5), (1.0, 10)])
        XCTAssertNil(PreambleDetector.preambleEnd(windowRMS: rms, windowDuration: 0.1))
    }

    func testNilForNoSilenceAllZeroOrEmpty() {
        XCTAssertNil(PreambleDetector.preambleEnd(windowRMS: windows([(1.0, 30)]), windowDuration: 0.1))
        XCTAssertNil(PreambleDetector.preambleEnd(windowRMS: windows([(0.0, 30)]), windowDuration: 0.1))
        XCTAssertNil(PreambleDetector.preambleEnd(windowRMS: [], windowDuration: 0.1))
        XCTAssertNil(PreambleDetector.preambleEnd(windowRMS: [1, 0, 1], windowDuration: 0))
    }

    func testSilenceIsRelativeToMedianLevel() {
        // Quiet-but-voiced windows (0.5 of median 1.0) are NOT silence;
        // windows at 0.1 of median are.
        let rms = windows([(1.0, 10), (0.5, 2), (1.0, 5), (0.1, 1), (1.0, 12)])
        XCTAssertEqual(PreambleDetector.preambleEnd(windowRMS: rms, windowDuration: 0.1)!,
                       18.0, accuracy: 0.11)
    }

    func testIgnoresSilenceRunTouchingArrayEnd() {
        // 10s speech followed by 2s silence with nothing after it — the run
        // is still open when the array ends. It must NOT be treated as the
        // preamble boundary: for a short section this silence is simply the
        // clip's trailing silence (or, for longer files, a run truncated by
        // the analysis window), not a pause before the chapter text.
        let rms = windows([(1.0, 10), (0.0, 2)])
        XCTAssertNil(PreambleDetector.preambleEnd(windowRMS: rms, windowDuration: 0.1))
    }
}
