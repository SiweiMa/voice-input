import SwiftUI

enum ConfigurationState {
    case disabled
    case ready
    case incomplete

    var title: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .ready:
            return "Ready"
        case .incomplete:
            return "Needs Setup"
        }
    }

    var tint: Color {
        switch self {
        case .disabled:
            return .secondary
        case .ready:
            return .green
        case .incomplete:
            return .voiceEmber
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var speechProvider: SpeechProvider = .apple
    @Published var llmEnabled = false
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

    var configurationState: ConfigurationState {
        guard llmEnabled else { return .disabled }
        return hasRequiredRefinementConfiguration ? .ready : .incomplete
    }

    var hasRequiredRefinementConfiguration: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !refinementModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var statusTint: Color {
        if statusMessage.hasPrefix("Success") || statusMessage == "Saved." {
            return .green
        }

        if statusMessage.hasPrefix("Testing") {
            return .voiceSky
        }

        return .voiceEmber
    }

    func reloadFromSettings() {
        speechProvider = settings.speechProvider
        llmEnabled = settings.llmEnabled
        baseURL = settings.apiBaseURL
        apiKey = settings.apiKey
        speechModel = settings.speechModel
        refinementModel = settings.refinementModel
        statusMessage = ""
    }

    func save() {
        settings.updateLLMEnabled(llmEnabled)
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
    @State private var revealAPIKey = false

    var body: some View {
        ZStack {
            SettingsBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroSection
                    transcriptionSection
                    refinementSection
                    footerSection
                }
                .padding(24)
            }
        }
        .frame(width: 720, height: 760)
    }

    private var heroSection: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 18) {
                AppLogoView(size: 84)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Voice Input")
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text("Choose your speech engine, optionally refine the transcript, and keep paste-ready text flowing.")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        CapsuleBadge(title: viewModel.speechProvider.displayName, tint: .voiceSky)
                        CapsuleBadge(title: viewModel.configurationState.title, tint: viewModel.configurationState.tint)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var transcriptionSection: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Transcription")
                        .font(.title3.weight(.semibold))

                    Text("Use Apple Speech by default, or switch to OpenAI when you want a different recognition backend.")
                        .foregroundStyle(.secondary)
                }

                SettingsField(title: "Speech Provider", caption: "Apple Speech is the default option.") {
                    Picker("Speech Provider", selection: $viewModel.speechProvider) {
                        ForEach(SpeechProvider.allCases, id: \.rawValue) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if viewModel.speechProvider == .openAI {
                    VStack(spacing: 14) {
                        SettingsField(title: "API Base URL", caption: "Example: https://api.openai.com/v1") {
                            TextField("https://api.openai.com/v1", text: $viewModel.baseURL)
                                .textFieldStyle(.plain)
                        }

                        HStack(alignment: .top, spacing: 14) {
                            SettingsField(title: "API Key", caption: "Stored locally on this Mac.") {
                                HStack(spacing: 12) {
                                    Group {
                                        if revealAPIKey {
                                            TextField("sk-...", text: $viewModel.apiKey)
                                        } else {
                                            SecureField("sk-...", text: $viewModel.apiKey)
                                        }
                                    }
                                    .textFieldStyle(.plain)

                                    Button(revealAPIKey ? "Hide" : "Reveal") {
                                        revealAPIKey.toggle()
                                    }
                                    .buttonStyle(.borderless)
                                    .foregroundStyle(.secondary)
                                }
                            }

                            SettingsField(title: "Speech Model", caption: "Example: whisper-1") {
                                TextField("whisper-1", text: $viewModel.speechModel)
                                    .textFieldStyle(.plain)
                            }
                        }
                    }
                } else {
                    Text("Apple Speech uses macOS permissions only. OpenAI API credentials are only needed if you later switch providers or enable refinement.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                }
            }
        }
    }

    private var refinementSection: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Refinement")
                            .font(.title3.weight(.semibold))

                        Text("Optionally clean up dictated text with an OpenAI-compatible endpoint before pasting.")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable refinement")
                            .font(.headline)

                        Text("When disabled, the raw transcript is pasted immediately.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $viewModel.llmEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .tint(.voiceEmber)
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                )

                VStack(spacing: 14) {
                    SettingsField(
                        title: "Shared API Endpoint",
                        caption: "Used for refinement, and also for OpenAI transcription if you select that provider."
                    ) {
                        TextField("https://api.openai.com/v1", text: $viewModel.baseURL)
                            .textFieldStyle(.plain)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        SettingsField(title: "Shared API Key", caption: "Stored locally on this Mac.") {
                            HStack(spacing: 12) {
                                Group {
                                    if revealAPIKey {
                                        TextField("sk-...", text: $viewModel.apiKey)
                                    } else {
                                        SecureField("sk-...", text: $viewModel.apiKey)
                                    }
                                }
                                .textFieldStyle(.plain)

                                Button(revealAPIKey ? "Hide" : "Reveal") {
                                    revealAPIKey.toggle()
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                            }
                        }

                        SettingsField(title: "Refinement Model", caption: "Example: gpt-4.1-mini") {
                            TextField("gpt-4.1-mini", text: $viewModel.refinementModel)
                                .textFieldStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var footerSection: some View {
        HStack(spacing: 14) {
            Group {
                if viewModel.statusMessage.isEmpty {
                    Text("Changes are saved locally. Use Test to validate the refinement endpoint before you rely on it.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(viewModel.statusMessage)
                        .foregroundStyle(viewModel.statusTint)
                }
            }
            .font(.subheadline.weight(.medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )

            Button(viewModel.isTesting ? "Testing..." : "Test") {
                viewModel.test()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(viewModel.isTesting || !viewModel.hasRequiredRefinementConfiguration)

            Button("Save") {
                viewModel.save()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.voiceEmber)
            .keyboardShortcut(.defaultAction)
        }
    }
}

private struct SettingsBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: NSColor.windowBackgroundColor),
                    Color.voiceMist.opacity(0.92),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.voiceSun.opacity(0.18))
                .frame(width: 280, height: 280)
                .blur(radius: 18)
                .offset(x: -240, y: -170)

            Circle()
                .fill(Color.voiceSky.opacity(0.14))
                .frame(width: 240, height: 240)
                .blur(radius: 22)
                .offset(x: 250, y: -120)

            Circle()
                .fill(Color.voiceEmber.opacity(0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 24)
                .offset(x: 150, y: 220)
        }
        .ignoresSafeArea()
    }
}

private struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 24, y: 12)
    }
}

private struct SettingsField<Content: View>: View {
    let title: String
    let caption: String
    let content: Content

    init(title: String, caption: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.secondary)

            content
                .font(.body.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.74))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.65), lineWidth: 1)
                )

            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CapsuleBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
    }
}
