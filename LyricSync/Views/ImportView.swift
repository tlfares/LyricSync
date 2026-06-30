import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundStyle(.tint)

            Text("LyricSync")
                .font(.largeTitle)
                .bold()

            Text("Import an audio file to automatically\ntranscribe the lyrics")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                viewModel.showFilePicker = true
            } label: {
                Label("Choose an audio file", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)

            if let song = viewModel.song {
                VStack(alignment: .leading, spacing: 8) {
                    Label("File imported", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                    Text(song.title)
                    Text(song.originalURL.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.importAudio(url: url)
                }
            case .failure(let error):
                viewModel.error = error.localizedDescription
            }
        }
    }
}
