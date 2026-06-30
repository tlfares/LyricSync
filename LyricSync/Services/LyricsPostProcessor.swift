import Foundation

struct ProcessedLine {
    let text: String
    let timeOffset: TimeInterval
    let duration: TimeInterval
    let confidence: Float
}

struct LyricsPostProcessor {
    func process(segments: [SegmentData]) -> [ProcessedLine] {
        guard !segments.isEmpty else { return [] }
        return buildLines(segments)
    }

    private func buildLines(_ segments: [SegmentData]) -> [ProcessedLine] {
        var result: [ProcessedLine] = []
        var current: [SegmentData] = []
        var recentGaps: [TimeInterval] = []
        let windowSize = 5
        let minWords = 2
        let maxWords = 10

        func shouldBreak(gap: TimeInterval, count: Int) -> Bool {
            guard count >= minWords else { return false }
            if count >= maxWords { return true }

            let localAvg = recentGaps.isEmpty ? gap : recentGaps.reduce(0, +) / Double(recentGaps.count)
            let ratio = localAvg > 0.01 ? gap / localAvg : 10

            if ratio > 2.5 && gap > 0.3 { return true }
            if gap > 1.2 { return true }
            if gap > 0.6 && count >= 4 { return true }

            return false
        }

        for i in 0..<segments.count {
            let seg = segments[i]
            guard !current.isEmpty else { current.append(seg); continue }

            let prevEnd = current.last!.timestamp + current.last!.duration
            let gap = seg.timestamp - prevEnd

            if gap > 0 {
                recentGaps.append(gap)
                if recentGaps.count > windowSize { recentGaps.removeFirst() }
            }

            if shouldBreak(gap: gap, count: current.count) {
                result.append(makeLine(current))
                current = [seg]
            } else {
                current.append(seg)
            }
        }

        if !current.isEmpty {
            if !result.isEmpty && current.count < 2 {
                var last = result.removeLast()
                last = ProcessedLine(
                    text: last.text + " " + current.map(\.text).joined(separator: " "),
                    timeOffset: last.timeOffset,
                    duration: (current.last?.timestamp ?? last.timeOffset) + (current.last?.duration ?? 0) - last.timeOffset,
                    confidence: (last.confidence + current.map(\.confidence).reduce(0, +) / Float(current.count)) / 2
                )
                result.append(last)
            } else {
                result.append(makeLine(current))
            }
        }

        return result
    }

    private func makeLine(_ segments: [SegmentData]) -> ProcessedLine {
        let text = segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let start = segments.first?.timestamp ?? 0
        let end = (segments.last?.timestamp ?? start) + (segments.last?.duration ?? 0)
        let avgConf = segments.map(\.confidence).reduce(0, +) / Float(max(segments.count, 1))
        return ProcessedLine(text: text, timeOffset: start, duration: end - start, confidence: avgConf)
    }
}
