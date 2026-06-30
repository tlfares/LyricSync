import SwiftUI

struct TranscriptionView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @State private var showLanguageSheet = false
    @FocusState private var focusedLineID: UUID?

    private enum QuickLang: String, CaseIterable {
        case french, english, other
    }

    private var quickLang: Binding<QuickLang> {
        Binding {
            switch viewModel.selectedLocale {
            case .french: return .french
            case .english: return .english
            default: return .other
            }
        } set: { newValue in
            switch newValue {
            case .french: viewModel.selectedLocale = .french
            case .english: viewModel.selectedLocale = .english
            case .other: showLanguageSheet = true
            }
        }
    }

    var body: some View {
        Group {
            if viewModel.isTranscribing {
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(viewModel.progressMessage)
                        .foregroundStyle(.secondary)

                    if viewModel.progress > 0 {
                        ProgressView(value: viewModel.progress)
                            .padding(.horizontal, 40)
                    }
                }
                .padding()
            } else if let song = viewModel.song, !song.lyrics.isEmpty {
                lyricList(song: song)
            } else if let song = viewModel.song, song.lyrics.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform")
                        .font(.system(size: 50))
                        .foregroundStyle(.tint)

                    Text("Prêt à transcrire")
                        .font(.title2)
                        .bold()

                    Text("\(song.title) — \(formatDuration(song.duration))")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    Toggle(isOn: $viewModel.usePastedLyrics) {
                        Label("J'ai déjà les paroles", systemImage: "doc.text")
                    }
                    .padding(.horizontal)

                    if viewModel.usePastedLyrics {
                        TextEditor(text: $viewModel.pastedLyrics)
                            .font(.body)
                            .frame(height: 200)
                            .overlay {
                                if viewModel.pastedLyrics.isEmpty {
                                    Text("Collez les paroles ici, un vers par ligne…")
                                        .foregroundStyle(.tertiary)
                                        .allowsHitTesting(false)
                                }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)

                        if !viewModel.pastedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("\(viewModel.parsePastedLyrics().count) vers détectés")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Langue", selection: quickLang) {
                        Text("Français").tag(QuickLang.french)
                        Text("English").tag(QuickLang.english)
                        Text("Autre…").tag(QuickLang.other)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if case .other = quickLang.wrappedValue {
                        Text(viewModel.selectedLocale.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if !viewModel.mistralSettings.enabled {
                        Picker("Mode", selection: $viewModel.recognitionMode) {
                            ForEach(RecognitionMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .overlay(alignment: .bottom) {
                            Text(viewModel.recognitionMode.description)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .offset(y: 18)
                        }
                        .padding(.bottom, 8)
                    }

                    Button {
                        viewModel.startTranscription()
                    } label: {
                        Label(
                            viewModel.usePastedLyrics ? "Synchroniser les paroles" : "Lancer la transcription",
                            systemImage: "play.fill"
                        )
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(viewModel.usePastedLyrics && viewModel.pastedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, 40)
                }
                .padding()
                .sheet(isPresented: $showLanguageSheet) {
                    NavigationStack {
                        List(TranscriptionLocale.allCases.filter { $0 != .french && $0 != .english }) { locale in
                            Button {
                                viewModel.selectedLocale = locale
                                showLanguageSheet = false
                            } label: {
                                HStack {
                                    Text(locale.displayName)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if viewModel.selectedLocale == locale {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                        .navigationTitle("Choisir la langue")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Annuler") { showLanguageSheet = false }
                            }
                        }
                    }
                    .presentationDetents([.medium, .large])
                }
            } else {
                ContentUnavailableView(
                    "Aucune chanson importée",
                    systemImage: "music.note",
                    description: Text("Importez d'abord un fichier audio depuis l'onglet Import")
                )
            }
        }
    }

    private func lyricList(song: Song) -> some View {
        List {
            Section {
                ForEach(song.lyrics) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(formatTimestamp(line.timeOffset))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()

                            Spacer()

                            if line.confidence < 0.5 {
                                Label("faible", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }

                        TextField("Parole", text: Binding(
                            get: { line.text },
                            set: { viewModel.updateLyricLine(id: line.id, newText: $0) }
                        ), axis: .vertical)
                        .lineLimit(1...10)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($focusedLineID, equals: line.id)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text("Paroles synchronisées")
                    Spacer()
                    Text("\(song.lyrics.count) lignes")
                        .foregroundStyle(.secondary)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Terminé") { focusedLineID = nil }
            }
        }
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let ms = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, ms)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
