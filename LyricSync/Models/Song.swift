import Foundation

struct Song: Identifiable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    var originalURL: URL
    var processedURL: URL?
    var lyrics: [LyricLine]
    var status: SongStatus
    var duration: TimeInterval

    init(id: UUID = UUID(), title: String = "", artist: String = "", album: String = "", originalURL: URL, processedURL: URL? = nil, lyrics: [LyricLine] = [], status: SongStatus = .imported, duration: TimeInterval = 0) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.originalURL = originalURL
        self.processedURL = processedURL
        self.lyrics = lyrics
        self.status = status
        self.duration = duration
    }

    enum SongStatus: Equatable {
        case imported
        case processing
        case transcribed
        case exporting
        case exported
        case failed(String)
    }
}
