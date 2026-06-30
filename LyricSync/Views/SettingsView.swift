import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Mistral API Key", text: $viewModel.mistralSettings.apiKey)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif

                    if !viewModel.mistralSettings.apiKey.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Key set")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Mistral AI")
                } footer: {
                    Text("Mistral is much more accurate than Apple Speech. The voxtral-mini model returns text+timestamps in one call, with LLM refinement for punctuation.")
                }

                Section {
                    Toggle("Use Mistral for transcription", isOn: $viewModel.mistralSettings.enabled)
                        .disabled(viewModel.mistralSettings.apiKey.isEmpty)
                } footer: {
                    if viewModel.mistralSettings.apiKey.isEmpty {
                        Text("Enter an API key above first")
                    } else {
                        Text("When enabled, all transcription (text + timing) is handled by Mistral. Apple Speech is not used.")
                    }
                }

                if !viewModel.mistralSettings.apiKey.isEmpty {
                    Section {
                        Button("Test connection", role: .none) {
                            Task { await testConnection() }
                        }
                        .disabled(viewModel.isTestingConnection)

                        if let testResult = viewModel.mistralConnectionTest {
                            Label(
                                testResult ? "Connection successful" : "Connection failed",
                                systemImage: testResult ? "checkmark.circle" : "xmark.circle"
                            )
                            .foregroundStyle(testResult ? .green : .red)
                        }
                    }
                }

                Section {
                    Button("Delete key", role: .destructive) {
                        viewModel.clearMistralKey()
                    }
                    .disabled(viewModel.mistralSettings.apiKey.isEmpty)
                }

                #if os(macOS)
                Section {
                    HStack {
                        Text("Output directory")
                        Spacer()
                        Text(viewModel.defaultOutputPath.isEmpty ? "Documents" : viewModel.defaultOutputPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Button("Choose…") {
                        showFolderPicker = true
                    }

                    if !viewModel.defaultOutputPath.isEmpty {
                        Button("Reset", role: .destructive) {
                            viewModel.defaultOutputPath = ""
                        }
                    }
                } header: {
                    Text("Export")
                } footer: {
                    Text("M4A and LRC files will be saved directly to this folder instead of showing the share sheet.")
                }
                .fileImporter(
                    isPresented: $showFolderPicker,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        viewModel.defaultOutputPath = url.path
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            #if os(macOS)
            .formStyle(.grouped)
            .frame(maxWidth: 600)
            #endif
        }
    }

    private func testConnection() async {
        await viewModel.testMistralConnection()
    }
}
