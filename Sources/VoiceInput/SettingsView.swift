import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var speechProvider: SpeechProvider = .apple
    @Published var baseURL = ""
    @Published var apiKey = ""
    @Published var speechModel = ""
    @Published var refinementModel = ""
    @Published var statusMessage = ""
    @Published var isTesting = false

    private let settings = AppSettings.shared
    private let refiner = LLMRefiner()

    init() {
        reloadFromSettings()
    }

    func reloadFromSettings() {
        speechProvider = settings.speechProvider
        baseURL = settings.apiBaseURL
        apiKey = settings.apiKey
        speechModel = settings.speechModel
        refinementModel = settings.refinementModel
        statusMessage = ""
    }

    func save() {
        settings.saveAPIConfiguration(
            speechProvider: speechProvider,
            baseURL: baseURL,
            apiKey: apiKey,
            speechModel: speechModel,
            refinementModel: refinementModel
        )
        statusMessage = "Saved."
    }

    func test() {
        let currentBaseURL = baseURL
        let currentAPIKey = apiKey
        let currentModel = refinementModel

        guard
            !currentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !currentAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !currentModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            statusMessage = "Fill in API Base URL, API Key, and Refinement Model first."
            return
        }

        isTesting = true
        statusMessage = "Testing..."

        Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let result = try await self.refiner.test(
                    baseURL: currentBaseURL,
                    apiKey: currentAPIKey,
                    model: currentModel
                )
                self.statusMessage = "Success: \(result)"
            } catch {
                self.statusMessage = error.localizedDescription
            }

            self.isTesting = false
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Speech & API Settings")
                .font(.title3.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    Text("Provider")
                        .frame(width: 96, alignment: .leading)
                    Picker("Provider", selection: $viewModel.speechProvider) {
                        ForEach(SpeechProvider.allCases, id: \.rawValue) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                GridRow {
                    Text("API Base URL")
                        .frame(width: 96, alignment: .leading)
                    TextField("https://api.openai.com/v1", text: $viewModel.baseURL)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("API Key")
                        .frame(width: 96, alignment: .leading)
                    TextField("sk-...", text: $viewModel.apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                GridRow {
                    Text("Speech Model")
                        .frame(width: 96, alignment: .leading)
                    TextField("whisper-1", text: $viewModel.speechModel)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.speechProvider == .apple)
                }

                GridRow {
                    Text("Refine Model")
                        .frame(width: 96, alignment: .leading)
                    TextField("gpt-4.1-mini", text: $viewModel.refinementModel)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text(footnoteText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()

                Button(viewModel.isTesting ? "Testing..." : "Test Refinement") {
                    viewModel.test()
                }
                .disabled(viewModel.isTesting)

                Button("Save") {
                    viewModel.save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 280)
    }

    private var footnoteText: String {
        switch viewModel.speechProvider {
        case .apple:
            return "Apple Speech is the default. OpenAI API settings are still used for optional LLM refinement."
        case .openAI:
            return "OpenAI speech-to-text uses the shared API Base URL, API Key, and Speech Model above. LLM refinement remains optional."
        }
    }
}
