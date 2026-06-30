import Foundation
import Speech
import AVFoundation

final class TranscriptionService: NSObject {
    enum TranscriptionError: Error, LocalizedError {
        case noResult
        case recognizerUnavailable
        case audioReadFailed
        case invalidAudio
        case notAuthorized
        case conversionFailed

        var errorDescription: String? {
            switch self {
            case .noResult: return "No transcription result"
            case .recognizerUnavailable: return "Speech recognition not available"
            case .audioReadFailed: return "Cannot read audio file"
            case .invalidAudio: return "Invalid or empty audio file"
            case .notAuthorized: return "Speech recognition authorization denied"
            case .conversionFailed: return "Cannot convert audio to 16kHz mono"
            }
        }
    }

    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withUnsafeContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    static func transcribe(url: URL, locale: Locale = Locale(identifier: "en-US"), contextualStrings: [String] = [], userLyrics: [String]? = nil) async throws -> [LyricLine] {
        let status = await requestAuthorization()
        guard status == .authorized else { throw TranscriptionError.notAuthorized }

        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let inputBuffer = try await readAudioFile(url: url)
        let monoBuffer = try convertToMono16kHz(inputBuffer)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        if !contextualStrings.isEmpty {
            request.contextualStrings = contextualStrings
        }

        let segments = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[SegmentData], Error>) in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: TranscriptionError.noResult)
                    return
                }
                let data = result.bestTranscription.segments.map { seg in
                    SegmentData(
                        text: seg.substring,
                        timestamp: seg.timestamp,
                        duration: seg.duration,
                        confidence: seg.confidence
                    )
                }
                continuation.resume(returning: data)
            }
            request.append(monoBuffer)
            request.endAudio()
        }

        if let userLyrics, !userLyrics.isEmpty {
            let aligned = alignWordsToUserLyrics(words: segments, userLines: userLyrics)
            return aligned.map {
                LyricLine(text: $0.text, timeOffset: $0.timeOffset, duration: $0.duration, confidence: $0.confidence)
            }
        }

        let processor = LyricsPostProcessor()
        let processed = processor.process(segments: segments)
        return processed.map {
            LyricLine(text: $0.text, timeOffset: $0.timeOffset, duration: $0.duration, confidence: $0.confidence)
        }
    }

    static func alignWordsToUserLyrics(words: [SegmentData], userLines: [String]) -> [ProcessedLine] {
        guard !words.isEmpty, !userLines.isEmpty else { return [] }
        let n = userLines.count
        let wordsPerLine = max(1, words.count / n)
        var result: [ProcessedLine] = []

        for i in 0..<n {
            let start = i * wordsPerLine
            let end = i == n - 1 ? words.count : min(start + wordsPerLine, words.count)
            guard start < end else { break }
            let slice = words[start..<end]
            let firstTime = slice.first!.timestamp
            let lastTime = slice.last!.timestamp + slice.last!.duration
            let avgConf = slice.map(\.confidence).reduce(0, +) / Float(slice.count)
            result.append(ProcessedLine(
                text: userLines[i],
                timeOffset: firstTime,
                duration: lastTime - firstTime,
                confidence: avgConf
            ))
        }
        return result
    }

    private static func readAudioFile(url: URL) async throws -> AVAudioPCMBuffer {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw TranscriptionError.audioReadFailed
        }

        let totalFrames = audioFile.length
        guard totalFrames > 0 else { throw TranscriptionError.invalidAudio }

        let format = audioFile.processingFormat
        let capacity = AVAudioFrameCount(totalFrames)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw TranscriptionError.audioReadFailed
        }
        try audioFile.read(into: buffer)
        guard buffer.frameLength > 0 else { throw TranscriptionError.invalidAudio }
        return buffer
    }

    private static func convertToMono16kHz(_ input: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        let inputFormat = input.format
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        if inputFormat.sampleRate == 16000 && inputFormat.channelCount == 1 {
            return input
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw TranscriptionError.conversionFailed
        }

        let inputFrames = AVAudioFrameCount(input.frameLength)
        let ratio = targetFormat.sampleRate / inputFormat.sampleRate
        let outputFrames = AVAudioFrameCount(Double(inputFrames) * ratio * 1.1)
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrames) else {
            throw TranscriptionError.conversionFailed
        }

        var error: NSError?
        let status = converter.convert(to: output, error: &error) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return input
        }

        guard status != .error else {
            throw TranscriptionError.conversionFailed
        }

        return output
    }

}

struct SegmentData: Sendable {
    let text: String
    let timestamp: TimeInterval
    let duration: TimeInterval
    let confidence: Float
}
