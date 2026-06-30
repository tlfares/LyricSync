import Foundation
import AVFoundation

actor LyricsExportService {
    enum ExportError: Error, LocalizedError {
        case exportFailed(Error?)
        case noAudioTrack
        case writerSetupFailed
        case readerSetupFailed
        case passthroughFailed

        var errorDescription: String? {
            switch self {
            case .exportFailed(let e): return e?.localizedDescription ?? "Export failed"
            case .noAudioTrack: return "No audio track found"
            case .writerSetupFailed: return "Cannot create output file"
            case .readerSetupFailed: return "Cannot read source file"
            case .passthroughFailed: return "Cannot export without re-encoding"
            }
        }
    }

    func exportWithLyrics(song: Song, outputDir: URL? = nil) async throws -> URL {
        let asset = AVAsset(url: song.originalURL)
        let baseDir = outputDir ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputURL = baseDir.appendingPathComponent("\(song.title)_lyrics.m4a")
        try? FileManager.default.removeItem(at: outputURL)

        let originalMetadata = (try? await loadAllMetadata(asset: asset)) ?? []
        let metadata = buildMetadata(from: song, original: originalMetadata)

        if let result = try? await passthroughExport(asset: asset, metadata: metadata, outputURL: outputURL) {
            return result
        }

        try? FileManager.default.removeItem(at: outputURL)
        return try await reencodeExport(asset: asset, metadata: metadata, outputURL: outputURL)
    }

    // MARK: - Passthrough (sans ré-encodage)

    private func passthroughExport(asset: AVAsset, metadata: [AVMutableMetadataItem], outputURL: URL) async throws -> URL {
        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else { throw ExportError.passthroughFailed }

        session.outputURL = outputURL
        session.outputFileType = .m4a
        session.metadata = metadata
        session.shouldOptimizeForNetworkUse = false

        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { c.resume() }
        }

        guard session.status == .completed else { throw ExportError.passthroughFailed }
        return outputURL
    }

    // MARK: - Ré-encodage 320 kbps

    private func reencodeExport(asset: AVAsset, metadata: [AVMutableMetadataItem], outputURL: URL) async throws -> URL {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let audioTrack = tracks.first else { throw ExportError.noAudioTrack }

        let formatDescs: [CMAudioFormatDescription] = try await audioTrack.load(.formatDescriptions)
        var sampleRate: Double = 44100
        var channels: Int = 2
        if let fd = formatDescs.first,
           let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
            sampleRate = asbd.mSampleRate
            channels = Int(asbd.mChannelsPerFrame)
        }

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: audioTrack,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        )
        guard reader.canAdd(readerOutput) else { throw ExportError.readerSetupFailed }
        reader.add(readerOutput)

        guard let writer = try? AVAssetWriter(url: outputURL, fileType: .m4a) else {
            throw ExportError.writerSetupFailed
        }
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 320000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ])
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else { throw ExportError.writerSetupFailed }
        writer.add(writerInput)
        writer.metadata = metadata

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        reader.startReading()

        let queue = DispatchQueue(label: "audio-export")
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sampleBuffer)
                    } else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            switch writer.status {
                            case .completed: continuation.resume(returning: outputURL)
                            default: continuation.resume(throwing: ExportError.exportFailed(writer.error))
                            }
                        }
                        break
                    }
                }
            }
        }
    }

    // MARK: - Metadata

    private func loadAllMetadata(asset: AVAsset) async throws -> [AVMetadataItem] {
        let common = try await asset.load(.commonMetadata)
        let formats = try await asset.load(.availableMetadataFormats)
        var all: [AVMetadataItem] = common
        for format in formats {
            let items = try await asset.loadMetadata(for: format)
            all.append(contentsOf: items)
        }
        return all
    }

    // MARK: - LRC Export

    func exportLRC(song: Song, outputDir: URL? = nil) async throws -> URL {
        let baseDir = outputDir ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputURL = baseDir.appendingPathComponent("\(song.title).lrc")
        try? FileManager.default.removeItem(at: outputURL)

        var lines: [String] = []
        for lyric in song.lyrics {
            let minutes = Int(lyric.timeOffset) / 60
            let seconds = Int(lyric.timeOffset) % 60
            let centiseconds = Int((lyric.timeOffset.truncatingRemainder(dividingBy: 1)) * 100)
            lines.append(String(format: "[%02d:%02d.%02d]%@", minutes, seconds, centiseconds, lyric.text))
        }
        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
        return outputURL
    }

    private func buildMetadata(from song: Song, original: [AVMetadataItem]) -> [AVMutableMetadataItem] {
        let plainText = song.lyrics.map(\.text).joined(separator: "\n")
        var result: [AVMutableMetadataItem] = []

        for item in original {
            let strKey = (item.key as? String) ?? ""
            let rawId = item.identifier?.rawValue ?? ""
            let isLyrics = rawId.lowercased().contains("lyric")
                || strKey.lowercased().contains("lyric")
                || strKey == "\u{00A9}lyr"
            if isLyrics { continue }
            if let copy = item.mutableCopy() as? AVMutableMetadataItem {
                result.append(copy)
            }
        }

        if !plainText.isEmpty {
            let lyrics = AVMutableMetadataItem()
            lyrics.identifier = .iTunesMetadataLyrics
            lyrics.value = plainText as NSString
            lyrics.dataType = kCMMetadataBaseDataType_UTF8 as String
            result.append(lyrics)
        }

        return result
    }
}
