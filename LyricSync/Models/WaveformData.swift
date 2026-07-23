import Foundation
import AVFoundation

struct WaveformData {
    let samples: [Float]
    let totalDuration: TimeInterval

    static func generate(from audioURL: URL, samplesPerSecond: Int = 30) async throws -> WaveformData {
        let asset = AVAsset(url: audioURL)
        let duration = try await asset.load(.duration)
        let totalDuration = CMTimeGetSeconds(duration)
        guard totalDuration > 0 else { throw WaveformError.emptyFile }

        let reader = try AVAssetReader(asset: asset)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else { throw WaveformError.noAudioTrack }

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVNumberOfChannelsKey: 1,
        ])
        guard reader.canAdd(output) else { throw WaveformError.readerFailed }
        reader.add(output)
        reader.startReading()

        let sourceSampleRate: Double = 16000
        let chunkSize = Int(sourceSampleRate) / samplesPerSecond

        var peaks: [Float] = []
        var buffer = [Int16](repeating: 0, count: chunkSize)
        var bufferIndex = 0
        var chunkMax: Float = 0

        while let buf = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(buf) {
            var length = 0
            var data: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &data)
            guard let ptr = data else { continue }
            let totalCount = length / MemoryLayout<Int16>.size

            ptr.withMemoryRebound(to: Int16.self, capacity: totalCount) { int16Ptr in
                for i in 0..<totalCount {
                    let val = abs(Float(int16Ptr[i]) / Float(Int16.max))
                    if val > chunkMax { chunkMax = val }
                    bufferIndex += 1
                    if bufferIndex >= chunkSize {
                        peaks.append(chunkMax)
                        chunkMax = 0
                        bufferIndex = 0
                    }
                }
            }
        }

        if bufferIndex > 0 { peaks.append(chunkMax) }

        reader.cancelReading()
        guard !peaks.isEmpty else { throw WaveformError.noSamples }

        return WaveformData(samples: peaks, totalDuration: totalDuration)
    }

    enum WaveformError: Error, LocalizedError {
        case emptyFile, noAudioTrack, readerFailed, noSamples
        var errorDescription: String? {
            switch self {
            case .emptyFile: return "Audio file is empty"
            case .noAudioTrack: return "No audio track found"
            case .readerFailed: return "Failed to read audio"
            case .noSamples: return "No audio samples found"
            }
        }
    }
}
