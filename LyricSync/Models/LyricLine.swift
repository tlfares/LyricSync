import Foundation

struct LyricLine: Identifiable, Codable {
    let id: UUID
    var text: String
    var timeOffset: TimeInterval
    var duration: TimeInterval
    var confidence: Float

    init(id: UUID = UUID(), text: String, timeOffset: TimeInterval, duration: TimeInterval = 0, confidence: Float = 1.0) {
        self.id = id
        self.text = text
        self.timeOffset = timeOffset
        self.duration = duration
        self.confidence = confidence
    }
}
