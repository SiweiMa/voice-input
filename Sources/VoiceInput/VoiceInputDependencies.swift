import AppKit
import Foundation

@MainActor
protocol AppSettingsStore: AnyObject {
    var selectedLanguage: AppLanguage { get }
    var speechProvider: SpeechProvider { get }
    var llmEnabled: Bool { get }
    var hasLLMConfiguration: Bool { get }
    var hasSpeechConfiguration: Bool { get }
    var apiBaseURL: String { get }
    var apiKey: String { get }
    var speechModel: String { get }
    var refinementModel: String { get }
    var effectiveSystemPrompt: String { get }

    func updateLanguage(_ language: AppLanguage)
    func updateSpeechProvider(_ provider: SpeechProvider)
    func updateLLMEnabled(_ enabled: Bool)
}

@MainActor
protocol FnKeyMonitoring: AnyObject {
    var onPressStateChanged: ((Bool) -> Void)? { get set }

    func start() -> Bool
    func stop()
}

@MainActor
protocol SpeechTranscribing: AnyObject {
    var onTranscriptChanged: ((String) -> Void)? { get set }
    var onLevelChanged: ((CGFloat) -> Void)? { get set }

    func start(
        provider: SpeechProvider,
        locale: Locale,
        languageCode: String,
        apiBaseURL: String,
        apiKey: String,
        model: String
    ) throws
    func stop() async throws -> String
    func cancel()
}

@MainActor
protocol OverlayControlling: AnyObject {
    func show()
    func updateTranscript(_ text: String)
    func updateStatus(_ text: String)
    func updateAudioLevel(_ level: CGFloat)
    func hide(after delay: TimeInterval)
    func hide()
}

struct PasteInjectionOutcome: Equatable {
    let clipboardWasRestored: Bool

    var statusMessage: String? {
        clipboardWasRestored ? nil : "Pasted without restoring clipboard"
    }
}

@MainActor
protocol PasteInjecting: AnyObject {
    func inject(text: String) async throws -> PasteInjectionOutcome
}

@MainActor
protocol LLMRefining: AnyObject {
    func refine(_ text: String, baseURL: String, apiKey: String, model: String, systemPrompt: String) async throws -> String
}

@MainActor
extension AppSettings: AppSettingsStore {}

@MainActor
extension FnKeyMonitor: FnKeyMonitoring {}

@MainActor
extension SpeechTranscriber: SpeechTranscribing {}

@MainActor
extension RecordingOverlayController: OverlayControlling {}

@MainActor
extension PasteInjector: PasteInjecting {}

@MainActor
extension LLMRefiner: LLMRefining {}
