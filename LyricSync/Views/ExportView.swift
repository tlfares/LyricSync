import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ExportView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        Group {
            if viewModel.exportedM4AURL != nil || viewModel.exportedLRCURL != nil {
                exportedView(m4aURL: viewModel.exportedM4AURL, lrcURL: viewModel.exportedLRCURL)
            } else if let song = viewModel.song, !song.lyrics.isEmpty {
                readyToExportView(song: song)
            } else if viewModel.isTranscribing {
                progressView
            } else {
                ContentUnavailableView(
                    "No file exported",
                    systemImage: "square.and.arrow.up",
                    description: Text("Transcribe a song first, then export it")
                )
            }
        }
    }

    private var progressView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text(viewModel.progressMessage)
                .foregroundStyle(.secondary)
        }
    }

    private func readyToExportView(song: Song) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text(song.title)
                .font(.title2)
                .bold()

            Picker("Export", selection: $viewModel.exportMode) {
                ForEach(TranscriptionViewModel.ExportMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if viewModel.exportMode != .m4aOnly {
                Picker("LRC title format", selection: $viewModel.lrcNamingFormat) {
                    ForEach(LyricsExportService.NamingFormat.allCases) { fmt in
                        Text(fmt.displayName).tag(fmt)
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("\(song.lyrics.count) lyric lines")
                } icon: {
                    Image(systemName: "text.alignleft")
                }

                if viewModel.exportMode != .lrcOnly {
                    Label {
                        Text("M4A with embedded lyrics (Apple Music)")
                    } icon: {
                        Image(systemName: "iphone")
                    }
                }

                if viewModel.exportMode != .m4aOnly {
                    Label {
                        Text("LRC for generic players")
                    } icon: {
                        Image(systemName: "doc.text")
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                viewModel.exportWithLyrics()
            } label: {
                Label("Export \(viewModel.exportMode.displayName)", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            #if os(macOS)
            .buttonStyle(.borderedProminent)
            .tint(Color.accentColor)
            #endif
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }

    private func exportedView(m4aURL: URL?, lrcURL: URL?) -> some View {
        #if os(macOS)
        let hasDefaultDir = !viewModel.defaultOutputPath.isEmpty
        #else
        let hasDefaultDir = false
        #endif

        let showM4A = m4aURL != nil
        let showLRC = lrcURL != nil

        return VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 70))
                .foregroundStyle(.green)

            Text("File\(showM4A && showLRC ? "s" : "") ready!")
                .font(.title)
                .bold()

            if hasDefaultDir, let url = m4aURL ?? lrcURL {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Saved to:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                #if os(macOS)
                Button {
                    let urls = [m4aURL, lrcURL].compactMap { $0 }
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .padding(.horizontal, 40)
                #endif
            }

            if !hasDefaultDir {
                if showM4A, let url = m4aURL {
                    ShareLink(item: url) {
                        Label("Share M4A (Apple Music)", systemImage: "iphone")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 40)
                }

                if showLRC, let url = lrcURL {
                    ShareLink(item: url) {
                        Label("Share LRC", systemImage: "doc.text")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.secondary)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 40)
                }
            }

            Spacer()
        }
    }
}
