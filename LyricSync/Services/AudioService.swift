import Foundation
import AVFoundation

actor AudioService {
    enum AudioError: Error, LocalizedError {
        case importFailed
        case conversionFailed
        case noAudioTrack
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .importFailed: return "Failed to import audio file"
            case .conversionFailed: return "Audio conversion failed"
            case .noAudioTrack: return "No audio track found"
            case .unsupportedFormat: return "Unsupported audio format"
            }
        }
    }

    func copyToSandbox(from url: URL) throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let uniqueName = "\(UUID().uuidString).\(url.pathExtension)"
        let dest = documents.appendingPathComponent(uniqueName)
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    func convertToWAV(for url: URL) async throws -> URL {
        let asset = AVAsset(url: url)

        let audioTracks = try? await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = audioTracks?.first else {
            throw AudioError.noAudioTrack
        }

        let formatDescriptions = try? await audioTrack.load(.formatDescriptions)
        if let desc = formatDescriptions?.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee,
           asbd.mFormatID == kAudioFormatLinearPCM {
            return url
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        guard reader.canAdd(readerOutput) else { throw AudioError.conversionFailed }
        reader.add(readerOutput)

        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let wavURL = documents.appendingPathComponent("\(UUID().uuidString).wav")

        let writer = try AVAssetWriter(url: wavURL, fileType: .wav)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        guard writer.canAdd(writerInput) else { throw AudioError.conversionFailed }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw AudioError.conversionFailed
        }
        writer.startSession(atSourceTime: .zero)
        guard reader.startReading() else {
            throw AudioError.conversionFailed
        }

        let queue = DispatchQueue(label: "audio.conversion")
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        writer.finishWriting { continuation.resume() }
                        return
                    }
                    writerInput.append(sampleBuffer)
                }
            }
        }

        guard writer.status == .completed else {
            throw AudioError.conversionFailed
        }
        return wavURL
    }

    nonisolated func getDuration(for url: URL) -> TimeInterval {
        let asset = AVAsset(url: url)
        return CMTimeGetSeconds(asset.duration)
    }
}
