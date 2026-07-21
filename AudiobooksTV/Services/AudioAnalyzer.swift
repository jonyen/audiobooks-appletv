import AVFoundation

/// Decodes the opening seconds of a local audio file into RMS loudness
/// windows for preamble detection.
enum AudioAnalyzer {
    static func rmsWindows(
        fileURL: URL, windowDuration: Double, limit: Double
    ) async throws -> [Float] {
        let asset = AVURLAsset(url: fileURL)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: limit, preferredTimescale: 600)
        )
        let sampleRate = 16_000.0
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ])
        reader.add(output)
        guard reader.startReading() else {
            throw reader.error ?? CocoaError(.fileReadUnknown)
        }

        let windowSamples = max(1, Int(sampleRate * windowDuration))
        var windows: [Float] = []
        var sumSquares = 0.0
        var samplesInWindow = 0

        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var totalLength = 0
            var lengthAtOffset = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(
                block, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset,
                totalLengthOut: &totalLength, dataPointerOut: &pointer
            ) == kCMBlockBufferNoErr, let pointer else { continue }
            // AVAssetReader's LPCM output is contiguous in practice, but
            // guard against a non-contiguous block buffer rather than
            // reading `totalLength` bytes through a pointer that's only
            // valid for `lengthAtOffset` of them.
            guard lengthAtOffset == totalLength else { continue }

            let sampleCount = totalLength / MemoryLayout<Float>.size
            pointer.withMemoryRebound(to: Float.self, capacity: sampleCount) { samples in
                for i in 0..<sampleCount {
                    let sample = Double(samples[i])
                    sumSquares += sample * sample
                    samplesInWindow += 1
                    if samplesInWindow == windowSamples {
                        windows.append(Float((sumSquares / Double(samplesInWindow)).squareRoot()))
                        sumSquares = 0
                        samplesInWindow = 0
                    }
                }
            }
        }
        if samplesInWindow > 0 {
            windows.append(Float((sumSquares / Double(samplesInWindow)).squareRoot()))
        }
        return windows
    }
}
