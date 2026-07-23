import SwiftUI

struct TranscriptionView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @State private var showLanguageSheet = false
    @FocusState private var focusedLineID: UUID?

    private struct TimeEditorContext: Identifiable, Equatable {
        let id = UUID()
        let lineID: UUID
        let currentTime: TimeInterval
        let text: String
    }
    @State private var timeEditorContext: TimeEditorContext?

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

                    Text("Ready to transcribe")
                        .font(.title2)
                        .bold()

                    Text("\(song.title) — \(formatDuration(song.duration))")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    Toggle(isOn: $viewModel.usePastedLyrics) {
                        Label("I already have the lyrics", systemImage: "doc.text")
                    }
                    .padding(.horizontal)

                    if viewModel.usePastedLyrics {
                        TextEditor(text: $viewModel.pastedLyrics)
                            .font(.body)
                            .frame(height: 200)
                            .overlay {
                                if viewModel.pastedLyrics.isEmpty {
                                    Text("Paste the lyrics here, one line per verse…")
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
                            Text("\(viewModel.parsePastedLyrics().count) verses detected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Language", selection: quickLang) {
                        Text("French").tag(QuickLang.french)
                        Text("English").tag(QuickLang.english)
                        Text("Other…").tag(QuickLang.other)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if case .other = quickLang.wrappedValue {
                        Text(viewModel.selectedLocale.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    let isMistral = viewModel.mistralSettings.enabled
                    let buttonColor: Color = isMistral ? Color(red: 1, green: 0.4157, blue: 0) : .accentColor
                    Button {
                        viewModel.startTranscription()
                    } label: {
                        Label(
                            isMistral ? "Transcript with Mistral" : viewModel.usePastedLyrics ? "Sync with audio" : "Start transcription",
                            systemImage: "play.fill"
                        )
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(buttonColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    #if os(macOS)
                    .buttonStyle(.borderedProminent)
                    .tint(buttonColor)
                    #endif
                    .disabled(viewModel.usePastedLyrics && viewModel.pastedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, 40)
                }
                .padding()
                .sheet(isPresented: $showLanguageSheet) {
                    NavigationStack {
                        List(TranscriptionLocale.allCases.filter { $0 != .french && $0 != .english }) { locale in
                            HStack {
                                Text(locale.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if viewModel.selectedLocale == locale {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedLocale = locale
                                showLanguageSheet = false
                            }
                        }
                        .navigationTitle("Choose a language")
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showLanguageSheet = false }
                            }
                        }
                    }
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
                    #else
                    .frame(minWidth: 300, minHeight: 400)
                    #endif
                }
                } else {
                ContentUnavailableView(
                    "No song imported",
                    systemImage: "music.note",
                    description: Text("Import an audio file first from the Import tab")
                )
            }
        }
        #if os(macOS)
        .buttonStyle(.plain)
        #endif
        .onChange(of: timeEditorContext) { _, _ in
            NotificationCenter.default.post(name: .waveformStopAll, object: nil)
        }
        .onDisappear {
            NotificationCenter.default.post(name: .waveformStopAll, object: nil)
        }
        .sheet(item: $timeEditorContext) { context in
            if let song = viewModel.song {
                WaveformEditorView(
                    audioURL: song.originalURL,
                    initialTime: context.currentTime,
                    verseText: context.text,
                    onConfirm: { newTime in
                        viewModel.updateLyricLineTime(id: context.lineID, newTime: newTime)
                        timeEditorContext = nil
                    },
                    onCancel: {
                        timeEditorContext = nil
                    }
                )
                .id(context.id)
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
                                .foregroundStyle(.tint)
                                .monospacedDigit()
                                .onTapGesture {
                                    timeEditorContext = TimeEditorContext(lineID: line.id, currentTime: line.timeOffset, text: line.text)
                                }
                                .help("Adjust timing")

                            Spacer()

                            if line.confidence < 0.5 {
                                Label("low", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }

                        TextField("Lyric", text: Binding(
                            get: { line.text },
                            set: { viewModel.updateLyricLine(id: line.id, newText: $0) }
                        ), axis: .vertical)
                        .lineLimit(1...10)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($focusedLineID, equals: line.id)

                        HStack {
                            Spacer()
                            Button {
                                if let idx = song.lyrics.firstIndex(where: { $0.id == line.id }) {
                                    viewModel.insertLyricLine(at: idx + 1)
                                }
                            } label: {
                                Label("Add verse", systemImage: "plus.circle")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { indexSet in
                    viewModel.deleteLyricLine(at: indexSet)
                }
            } header: {
                HStack {
                    Text("Synced lyrics")
                    Spacer()
                    Text("\(song.lyrics.count) lines")
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                viewModel.insertLyricLine(at: song.lyrics.count)
            } label: {
                Label("Add verse", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedLineID = nil }
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
