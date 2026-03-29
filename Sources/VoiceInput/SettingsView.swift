import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var baseURL = ""
    @Published var apiKey = ""
    @Published var model = ""
    @Published var statusMessage = ""
    @Published var isTesting = false

    private let settings = AppSettings.shared
    private let refiner = LLMRefiner()

    init() {
        reloadFromSettings()
    }

    func reloadFromSettings() {
        baseURL = settings.apiBaseURL
        apiKey = settings.apiKey
        model = settings.model
        statusMessage = ""
    }

    func save() {
        settings.saveLLMConfiguration(baseURL: baseURL, apiKey: apiKey, model: model)
        statusMessage = "Saved."
    }

    func test() {
        let currentBaseURL = baseURL
        let currentAPIKey = apiKey
        let currentModel = model

        guard
            !currentBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !currentAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !currentModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            statusMessage = "Fill in API Base URL, API Key, and Model first."
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
            Text("OpenAI-Compatible LLM Refinement")
                .font(.title3.weight(.semibold))

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 14) {
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
                    Text("Model")
                        .frame(width: 96, alignment: .leading)
                    TextField("gpt-4.1-mini", text: $viewModel.model)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack(spacing: 12) {
                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()

                Button(viewModel.isTesting ? "Testing..." : "Test") {
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
        .frame(width: 560, height: 220)
    }
}
