import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TranscriptionViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ImportView(viewModel: viewModel)
                .tabItem {
                    Label("Import", systemImage: "doc.badge.plus")
                }
                .tag(0)

            TranscriptionView(viewModel: viewModel)
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }
                .tag(1)

            ExportView(viewModel: viewModel)
                .tabItem {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .tag(2)

            SettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(3)
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            Text(viewModel.error ?? "")
        }
    }
}
