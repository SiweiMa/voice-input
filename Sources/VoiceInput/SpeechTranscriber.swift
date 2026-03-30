import Foundation

@MainActor
protocol SpeechBackendTranscribing: AnyObject {
    var onTranscriptChanged: ((String) -> Void)? { get set }
    var onLevelChanged: ((CGFloat) -> Void)? { get set }

    func start(locale: Locale, languageCode: String, apiBaseURL: String, apiKey: String, model: String) throws
    func stop() async throws -> String
    func cancel()
}

@MainActor
final class SpeechTranscriber {
    var onTranscriptChanged: ((String) -> Void)?
    var onLevelChanged: ((CGFloat) -> Void)?

    private let appleTranscriber: SpeechBackendTranscribing
    private let openAITranscriber: SpeechBackendTranscribing
    private var activeTranscriber: SpeechBackendTranscribing?

    init(
        appleTranscriber: SpeechBackendTranscribing? = nil,
        openAITranscriber: SpeechBackendTranscribing? = nil
    ) {
        self.appleTranscriber = appleTranscriber ?? AppleSpeechTranscriber()
        self.openAITranscriber = openAITranscriber ?? OpenAISpeechTranscriber()
    }

    func start(
        provider: SpeechProvider,
        locale: Locale,
        languageCode: String,
        apiBaseURL: String,
        apiKey: String,
        model: String
    ) throws {
        let transcriber = transcriber(for: provider)
        wireCallbacks(into: transcriber)

        appleTranscriber.cancel()
        openAITranscriber.cancel()
        activeTranscriber = transcriber

        try transcriber.start(
            locale: locale,
            languageCode: languageCode,
            apiBaseURL: apiBaseURL,
            apiKey: apiKey,
            model: model
        )
    }

    func stop() async throws -> String {
        try await activeTranscriber?.stop() ?? ""
    }

    func cancel() {
        appleTranscriber.cancel()
        openAITranscriber.cancel()
        activeTranscriber = nil
    }

    private func transcriber(for provider: SpeechProvider) -> SpeechBackendTranscribing {
        switch provider {
        case .apple:
            return appleTranscriber
        case .openAI:
            return openAITranscriber
        }
    }

    private func wireCallbacks(into transcriber: SpeechBackendTranscribing) {
        transcriber.onTranscriptChanged = { [weak self] transcript in
            self?.onTranscriptChanged?(transcript)
        }

        transcriber.onLevelChanged = { [weak self] level in
            self?.onLevelChanged?(level)
        }
    }
}
