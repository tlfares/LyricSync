import Foundation
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@MainActor
class TranscriptionViewModel: ObservableObject {
    enum ExportMode: String, CaseIterable, Identifiable {
        case both, m4aOnly, lrcOnly
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .both: return "M4A + LRC"
            case .m4aOnly: return "M4A only"
            case .lrcOnly: return "LRC only"
            }
        }
    }

    enum ImportError: Error, LocalizedError {
        case accessDenied

        var errorDescription: String? {
            switch self {
            case .accessDenied: return "Cannot access file (insufficient permissions)"
            }
        }
    }
    @Published var song: Song?
    @Published var isTranscribing = false
    @Published var progress: Double = 0
    @Published var progressMessage: String = ""
    @Published var error: String?
    @Published var showFilePicker = false
    @Published var showShareSheet = false
    @Published var exportedM4AURL: URL?
    @Published var exportedLRCURL: URL?
    @Published var defaultOutputPath: String = "" {
        didSet { UserDefaults.standard.set(defaultOutputPath, forKey: "defaultOutputPath") }
    }
    @Published var selectedLocale: TranscriptionLocale = .english
    @Published var exportMode: ExportMode = .both
    @Published var usePastedLyrics = false
    @Published var pastedLyrics: String = ""
    @Published var mistralSettings = MistralSettings()
    @Published var isTestingConnection = false
    @Published var mistralConnectionTest: Bool?

    private let audioService = AudioService()
    private let exportService = LyricsExportService()

    init() {
        let savedKey = KeychainHelper.load(key: "api_key") ?? ""
        mistralSettings.apiKey = savedKey
        mistralSettings.enabled = !savedKey.isEmpty || UserDefaults.standard.bool(forKey: "mistral_enabled")
        defaultOutputPath = UserDefaults.standard.string(forKey: "defaultOutputPath") ?? ""
    }

    var canTranscribe: Bool {
        song != nil && !isTranscribing
    }

    var canExport: Bool {
        guard let song else { return false }
        return !song.lyrics.isEmpty && !isTranscribing
    }

    func importAudio(url: URL) {
        Task {
            do {
                progressMessage = "Importing audio file..."
                guard url.startAccessingSecurityScopedResource() else {
                    throw ImportError.accessDenied
                }
                defer { url.stopAccessingSecurityScopedResource() }

                let sandboxURL = try await audioService.copyToSandbox(from: url)

                let asset = AVAsset(url: url)
                let duration = try? await asset.load(.duration)
                let durationSecs = CMTimeGetSeconds(duration ?? .zero)

                var title = url.deletingPathExtension().lastPathComponent
                var artist = "Unknown artist"

                if let metadata = try? await asset.load(.commonMetadata) {
                    for item in metadata {
                        if item.commonKey == .commonKeyTitle {
                            title = (try? await item.load(.value)) as? String ?? title
                        } else if item.commonKey == .commonKeyArtist {
                            artist = (try? await item.load(.value)) as? String ?? artist
                        }
                    }
                }

                let song = Song(
                    title: title,
                    artist: artist,
                    originalURL: sandboxURL,
                    duration: durationSecs
                )
                self.song = song
                progressMessage = "File imported successfully"
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func startTranscription() {
        guard let song = song else { return }

        Task {
            do {
                isTranscribing = true
                progress = 0

                let useMistral = mistralSettings.enabled
                    && !mistralSettings.apiKey.isEmpty
                    && !usePastedLyrics

                // — Mistral : transcription + timestamps en un appel —
                if useMistral {
                    progressMessage = "Transcribing with Mistral..."
                    let lyrics = try await MistralService.transcribe(
                        audioURL: song.originalURL,
                        apiKey: mistralSettings.apiKey
                    )
                    progress = 0.8

                    guard !lyrics.isEmpty else {
                        throw TranscriptionService.TranscriptionError.noResult
                    }

                    self.song?.lyrics = lyrics
                } else {
                    // — Mode normal (Apple uniquement) —
                    progressMessage = usePastedLyrics ? "Syncing..." : "Transcribing..."
                    let lyrics = try await TranscriptionService.transcribe(
                        url: song.originalURL,
                        locale: selectedLocale.locale,
                        contextualStrings: [song.title, song.artist].filter { !$0.isEmpty && $0 != "Unknown artist" },
                        userLyrics: usePastedLyrics ? parsePastedLyrics() : nil
                    )
                    self.song?.lyrics = lyrics
                }

                progress = 0.9
                self.song?.status = .transcribed
                progress = 1.0
                progressMessage = "Done (\(self.song?.lyrics.count ?? 0) lines)"
            } catch {
                self.error = error.localizedDescription
                self.song?.status = .failed(error.localizedDescription)
            }
            isTranscribing = false
        }
    }

    func parsePastedLyrics() -> [String] {
        pastedLyrics
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func exportWithLyrics() {
        guard let song = song else { return }

        Task {
            do {
                isTranscribing = true
                self.song?.status = .exporting
                let outputDir: URL? = resolvedOutputDir()

                switch exportMode {
                case .both:
                    progressMessage = "Exporting M4A + LRC..."
                    let url = try await exportService.exportWithLyrics(song: song, outputDir: outputDir)
                    exportedM4AURL = url
                    do {
                        exportedLRCURL = try await exportService.exportLRC(song: song, outputDir: outputDir)
                    } catch {
                        exportedLRCURL = nil
                    }
                case .m4aOnly:
                    progressMessage = "Exporting M4A..."
                    let url = try await exportService.exportWithLyrics(song: song, outputDir: outputDir)
                    exportedM4AURL = url
                    exportedLRCURL = nil
                case .lrcOnly:
                    progressMessage = "Exporting LRC..."
                    let url = try await exportService.exportLRC(song: song, outputDir: outputDir)
                    exportedLRCURL = url
                    exportedM4AURL = nil
                }

                self.song?.status = .exported
                progressMessage = "Export complete!"
                showShareSheet = true
            } catch {
                self.error = error.localizedDescription
                self.song?.status = .failed(error.localizedDescription)
            }
            isTranscribing = false
        }
    }

    func resolvedOutputDir() -> URL? {
        let path = defaultOutputPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return URL(fileURLWithPath: path)
    }

    func updateLyricLine(id: UUID, newText: String) {
        guard let index = song?.lyrics.firstIndex(where: { $0.id == id }) else { return }
        song?.lyrics[index].text = newText
    }

    func testMistralConnection() async {
        isTestingConnection = true
        mistralConnectionTest = nil
        do {
            var request = URLRequest(url: URL(string: "https://api.mistral.ai/v1/models")!)
            request.setValue("Bearer \(mistralSettings.apiKey)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await URLSession.shared.data(for: request)
            mistralConnectionTest = (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            mistralConnectionTest = false
        }
        isTestingConnection = false
    }

    func clearMistralKey() {
        mistralSettings.apiKey = ""
        mistralSettings.enabled = false
        KeychainHelper.delete(key: "api_key")
        UserDefaults.standard.set(false, forKey: "mistral_enabled")
    }
}

struct MistralSettings {
    var apiKey: String = "" {
        didSet {
            KeychainHelper.save(key: "api_key", value: apiKey)
        }
    }
    var enabled: Bool = false {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "mistral_enabled")
        }
    }
}

enum TranscriptionLocale: String, CaseIterable, Identifiable {
    case english
    case french
    case spanish
    case german
    case italian
    case portuguese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .french: return "Français"
        case .spanish: return "Español"
        case .german: return "Deutsch"
        case .italian: return "Italiano"
        case .portuguese: return "Português"
        }
    }

    var locale: Locale {
        switch self {
        case .english: return Locale(identifier: "en-US")
        case .french: return Locale(identifier: "fr-FR")
        case .spanish: return Locale(identifier: "es-ES")
        case .german: return Locale(identifier: "de-DE")
        case .italian: return Locale(identifier: "it-IT")
        case .portuguese: return Locale(identifier: "pt-BR")
        }
    }
}
