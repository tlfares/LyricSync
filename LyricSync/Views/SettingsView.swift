import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Clé API Mistral", text: $viewModel.mistralSettings.apiKey)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif

                    if !viewModel.mistralSettings.apiKey.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Clé configurée")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Mistral AI")
                } footer: {
                    Text("Mistral est beaucoup plus précis que Apple Speech. Le modèle voxtral-mini retourne directement texte+timestamps, avec un raffinement par LLM pour la ponctuation.")
                }

                Section {
                    Toggle("Utiliser Mistral pour la transcription", isOn: $viewModel.mistralSettings.enabled)
                        .disabled(viewModel.mistralSettings.apiKey.isEmpty)
                } footer: {
                    if viewModel.mistralSettings.apiKey.isEmpty {
                        Text("Entrez d'abord une clé API ci-dessus")
                    } else {
                        Text("Quand activé, toute la transcription (texte + timings) est gérée par Mistral. Apple Speech n'est pas utilisé.")
                    }
                }

                if !viewModel.mistralSettings.apiKey.isEmpty {
                    Section {
                        Button("Tester la connexion", role: .none) {
                            Task { await testConnection() }
                        }
                        .disabled(viewModel.isTestingConnection)

                        if let testResult = viewModel.mistralConnectionTest {
                            Label(
                                testResult ? "Connexion réussie" : "Échec de la connexion",
                                systemImage: testResult ? "checkmark.circle" : "xmark.circle"
                            )
                            .foregroundStyle(testResult ? .green : .red)
                        }
                    }
                }

                Section {
                    Button("Supprimer la clé", role: .destructive) {
                        viewModel.clearMistralKey()
                    }
                    .disabled(viewModel.mistralSettings.apiKey.isEmpty)
                }

                #if os(macOS)
                Section {
                    HStack {
                        Text("Dossier de sortie")
                        Spacer()
                        Text(viewModel.defaultOutputPath.isEmpty ? "Documents" : viewModel.defaultOutputPath)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Button("Choisir…") {
                        showFolderPicker = true
                    }

                    if !viewModel.defaultOutputPath.isEmpty {
                        Button("Réinitialiser", role: .destructive) {
                            viewModel.defaultOutputPath = ""
                        }
                    }
                } header: {
                    Text("Export")
                } footer: {
                    Text("Les fichiers M4A et LRC seront sauvegardés directement dans ce dossier au lieu d'afficher la feuille de partage.")
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
            .navigationTitle("Réglages")
            #if os(macOS)
            .padding(.horizontal)
            #endif
        }
    }

    private func testConnection() async {
        await viewModel.testMistralConnection()
    }
}
