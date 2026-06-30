import Foundation
import NaturalLanguage

struct MistralService {
    enum MistralError: Error, LocalizedError {
        case noAPIKey
        case networkError(Error)
        case badResponse(Int, String)
        case noData
        case parseFailed

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "Clé API Mistral non configurée"
            case .networkError(let e): return "Erreur réseau : \(e.localizedDescription)"
            case .badResponse(let code, let body): return "Mistral a répondu \(code) : \(body)"
            case .noData: return "Aucune réponse de Mistral"
            case .parseFailed: return "Impossible de lire la réponse Mistral"
            }
        }
    }

    private static let audioEndpoint = "https://api.mistral.ai/v1/audio/transcriptions"
    private static let chatEndpoint = "https://api.mistral.ai/v1/chat/completions"

    static func transcribe(audioURL: URL, apiKey: String) async throws -> [LyricLine] {
        guard !apiKey.isEmpty else { throw MistralError.noAPIKey }

        let segments = try await transcribeAudio(audioURL: audioURL, apiKey: apiKey)
        guard !segments.isEmpty else { return [] }

        do {
            return try await refinePunctuation(segments: segments, apiKey: apiKey)
        } catch {
            let tokenizer = NLTokenizer(unit: .sentence)
            var result: [LyricLine] = []
            for seg in segments {
                let sentences = splitSentences(seg.text, tokenizer: tokenizer)
                let count = sentences.count
                for (j, sentence) in sentences.enumerated() {
                    let lineStart = seg.timeOffset + seg.duration * Double(j) / Double(count)
                    let lineDuration = seg.duration / Double(count)
                    result.append(LyricLine(text: sentence, timeOffset: lineStart, duration: max(lineDuration, 0.1)))
                }
            }
            return result.isEmpty ? segments : result
        }
    }

    private static func splitSentences(_ text: String, tokenizer: NLTokenizer) -> [String] {
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { sentences.append(sentence) }
            return true
        }
        return sentences
    }

    // MARK: - Transcription audio

    private static func transcribeAudio(audioURL: URL, apiKey: String) async throws -> [LyricLine] {
        var request = URLRequest(url: URL(string: audioEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func append(_ str: String) { body.append(str.data(using: .utf8)!) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("voxtral-mini-latest\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n")
        append("0.0\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"timestamp_granularities\"\r\n\r\n")
        append("segment\r\n")

        let audioData = try Data(contentsOf: audioURL)
        let ext = audioURL.pathExtension.lowercased()
        let mime: String
        switch ext {
        case "mp3": mime = "audio/mpeg"
        case "wav": mime = "audio/wav"
        case "aiff", "aif": mime = "audio/aiff"
        default: mime = "audio/mp4"
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.\(ext)\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(audioData)
        append("\r\n")

        append("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MistralError.badResponse(0, "")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorText = String(data: data, encoding: .utf8) ?? "inconnu"
            throw MistralError.badResponse(httpResponse.statusCode, errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MistralError.parseFailed
        }

        let rawSegments = json["segments"] as? [[String: Any]] ?? []

        if rawSegments.isEmpty {
            if let rawText = json["text"] as? String {
                return [LyricLine(text: rawText, timeOffset: 0, duration: 0)]
            }
            throw MistralError.parseFailed
        }

        var result: [LyricLine] = []
        for seg in rawSegments {
            let text = (seg["text"] as? String) ?? ""
            let start = seg["start"] as? Double ?? 0
            let end = seg["end"] as? Double ?? 0
            result.append(LyricLine(
                text: text.trimmingCharacters(in: .whitespaces),
                timeOffset: start,
                duration: max(end - start, 0.1)
            ))
        }
        return result
    }

    // MARK: - Raffinage ponctuation par LLM

    private static func refinePunctuation(segments: [LyricLine], apiKey: String) async throws -> [LyricLine] {
        let fullText = segments.map(\.text).joined(separator: " ")
        guard !fullText.isEmpty else { return segments }

        var request = URLRequest(url: URL(string: chatEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = """
        Add a period at the end of each sentence in the lyrics below, but ONLY if a new sentence starts with a capitalized word that is NOT a proper noun (name, place, deity). If a capitalized word IS a proper noun, do NOT insert a period before it.

        Return ONLY the formatted lyrics, one sentence per line. Do NOT change any words. Do NOT add any explanation.

        Examples:
        Input: "The captain gave a shout The harpoons deployed The first mate was annoyed"
        Output: "The captain gave a shout. The harpoons deployed. The first mate was annoyed"

        Input: "Jesus he revealed The magic tricks and trash Of his soul patch and mustache"
        Output: "Jesus he revealed the magic tricks and trash of his soul patch and mustache"
        (No periods added because the capitalized words are after line breaks in poetic context — be smart about it)

        Input: "I wandered away confused And noticed that he'd taken my shoes"
        Output: "I wandered away confused. And noticed that he'd taken my shoes"

        Input: "My feet in the mud and sand As the ocean turned to land And I stared out all wide-eyed"
        Output: "My feet in the mud and sand. As the ocean turned to land. And I stared out all wide-eyed"

        Now process these lyrics:
        \(fullText)
        """

        let bodyDict: [String: Any] = [
            "model": "mistral-large-latest",
            "messages": [
                ["role": "system", "content": "You are a lyrics formatting assistant. Add punctuation only where grammatically needed. Never change words. Return one sentence per line."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.0,
            "max_tokens": 2048
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let errorText = String(data: data, encoding: .utf8) ?? "inconnu"
            throw MistralError.badResponse(code, errorText)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw MistralError.parseFailed
        }

        let rawLines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !rawLines.isEmpty else { return segments }

        return alignTimings(rawLines: rawLines, originalSegments: segments)
    }

    private static func alignTimings(rawLines: [String], originalSegments: [LyricLine]) -> [LyricLine] {
        let rawWords = originalSegments.map { seg in
            seg.text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        }
        let totalWords = rawWords.reduce(0) { $0 + $1.count }
        guard totalWords > 0 else { return originalSegments }

        var wordIndex = 0
        var result: [LyricLine] = []

        for line in rawLines {
            let words = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard !words.isEmpty else { continue }

            let wordCount = words.count
            let endIndex = min(wordIndex + wordCount, totalWords)
            guard endIndex > wordIndex else { continue }

            var cumulative = 0
            var startSeg = 0
            var startOffset = 0.0
            for (i, segWords) in rawWords.enumerated() {
                let next = cumulative + segWords.count
                if wordIndex < next {
                    let posInSeg = wordIndex - cumulative
                    let segDuration = originalSegments[i].duration
                    let segStart = originalSegments[i].timeOffset
                    startOffset = segStart + segDuration * Double(posInSeg) / Double(max(segWords.count, 1))
                    startSeg = i
                    break
                }
                cumulative = next
            }

            var endOffset = startOffset
            if endIndex > wordIndex {
                var cum2 = 0
                for (i, segWords) in rawWords.enumerated() {
                    let next = cum2 + segWords.count
                    if endIndex - 1 < next {
                        let posInSeg = (endIndex - 1) - cum2
                        let segDuration = originalSegments[i].duration
                        let segStart = originalSegments[i].timeOffset
                        endOffset = segStart + segDuration * Double(posInSeg + 1) / Double(max(segWords.count, 1))
                        break
                    }
                    cum2 = next
                }
            }

            result.append(LyricLine(
                text: line,
                timeOffset: startOffset,
                duration: max(endOffset - startOffset, 0.1)
            ))

            wordIndex = endIndex
        }

        return result.isEmpty ? originalSegments : result
    }
}
