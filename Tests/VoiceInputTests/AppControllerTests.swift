import XCTest
@testable import VoiceInput

@MainActor
final class AppControllerTests: XCTestCase {
    func testRefinementFailureFallsBackToRawTranscript() async {
        let settings = FakeSettings(llmEnabled: true, hasLLMConfiguration: true)
        let transcriber = FakeTranscriber(stopResult: "raw transcript")
        let overlay = FakeOverlayController()
        let pasteInjector = FakePasteInjector()
        let llmRefiner = FakeLLMRefiner(result: .failure(FakeError.refineFailed))
        let controller = AppController(
            settings: settings,
            fnKeyMonitor: FakeFnKeyMonitor(),
            transcriber: transcriber,
            overlayController: overlay,
            pasteInjector: pasteInjector,
            llmRefiner: llmRefiner
        )

        controller.handlePressStateChanged(true)
        controller.handlePressStateChanged(false)
        await waitForPaste(in: pasteInjector)

        XCTAssertEqual(pasteInjector.injectedTexts, ["raw transcript"])
        XCTAssertTrue(overlay.statusMessages.contains("Refine failed"))
        XCTAssertEqual(overlay.transcripts.last, "raw transcript")
    }

    func testClipboardFallbackMessageIsShownWhenClipboardCannotBeRestored() async {
        let transcriber = FakeTranscriber(stopResult: "final text")
        let overlay = FakeOverlayController()
        let pasteInjector = FakePasteInjector(outcome: PasteInjectionOutcome(clipboardWasRestored: false))
        let controller = AppController(
            settings: FakeSettings(),
            fnKeyMonitor: FakeFnKeyMonitor(),
            transcriber: transcriber,
            overlayController: overlay,
            pasteInjector: pasteInjector,
            llmRefiner: FakeLLMRefiner()
        )

        controller.handlePressStateChanged(true)
        controller.handlePressStateChanged(false)
        await waitForPaste(in: pasteInjector)

        XCTAssertEqual(overlay.statusMessages.last, "Pasted without restoring clipboard")
        XCTAssertEqual(overlay.hideDelays.last, 1.0)
    }

    func testStopCancelsOutstandingFinalizationWork() async {
        let transcriber = FakeTranscriber(stopResult: "final text", shouldSuspendStop: true)
        let overlay = FakeOverlayController()
        let pasteInjector = FakePasteInjector()
        let llmRefiner = FakeLLMRefiner(delayNanoseconds: 500_000_000)
        let controller = AppController(
            settings: FakeSettings(llmEnabled: true, hasLLMConfiguration: true),
            fnKeyMonitor: FakeFnKeyMonitor(),
            transcriber: transcriber,
            overlayController: overlay,
            pasteInjector: pasteInjector,
            llmRefiner: llmRefiner
        )

        controller.handlePressStateChanged(true)
        controller.handlePressStateChanged(false)
        controller.stop()

        transcriber.resumeStop()
        await Task.yield()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(pasteInjector.injectedTexts.isEmpty)
        XCTAssertNotEqual(overlay.statusMessages.last, "Pasted without restoring clipboard")
    }

    private func waitForPaste(in pasteInjector: FakePasteInjector) async {
        for _ in 0..<60 {
            if !pasteInjector.injectedTexts.isEmpty {
                return
            }

            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTFail("Timed out waiting for paste injection")
    }
}

@MainActor
private final class FakeSettings: AppSettingsStore {
    var selectedLanguage: AppLanguage = .english
    var speechProvider: SpeechProvider = .apple
    var llmEnabled: Bool
    var hasLLMConfiguration: Bool
    var hasSpeechConfiguration = true
    var apiBaseURL = "https://example.com/v1"
    var apiKey = "key"
    var speechModel = "whisper-1"
    var refinementModel = "model"

    init(llmEnabled: Bool = false, hasLLMConfiguration: Bool = false) {
        self.llmEnabled = llmEnabled
        self.hasLLMConfiguration = hasLLMConfiguration
    }

    func updateLanguage(_ language: AppLanguage) {
        selectedLanguage = language
    }

    func updateSpeechProvider(_ provider: SpeechProvider) {
        speechProvider = provider
    }

    func updateLLMEnabled(_ enabled: Bool) {
        llmEnabled = enabled
    }
}

@MainActor
private final class FakeFnKeyMonitor: FnKeyMonitoring {
    var onPressStateChanged: ((Bool) -> Void)?

    func start() -> Bool {
        true
    }

    func stop() {}
}

@MainActor
private final class FakeTranscriber: SpeechTranscribing {
    var onTranscriptChanged: ((String) -> Void)?
    var onLevelChanged: ((CGFloat) -> Void)?

    private let stopResult: String
    private let shouldSuspendStop: Bool
    private var stopContinuation: CheckedContinuation<String, Never>?

    init(stopResult: String, shouldSuspendStop: Bool = false) {
        self.stopResult = stopResult
        self.shouldSuspendStop = shouldSuspendStop
    }

    func start(
        provider: SpeechProvider,
        locale: Locale,
        languageCode: String,
        apiBaseURL: String,
        apiKey: String,
        model: String
    ) throws {
        onTranscriptChanged?("")
    }

    func stop() async throws -> String {
        if shouldSuspendStop {
            return await withCheckedContinuation { continuation in
                stopContinuation = continuation
            }
        }

        return stopResult
    }

    func cancel() {
        stopContinuation?.resume(returning: stopResult)
        stopContinuation = nil
    }

    func resumeStop() {
        cancel()
    }
}

@MainActor
private final class FakeOverlayController: OverlayControlling {
    private(set) var statusMessages: [String] = []
    private(set) var transcripts: [String] = []
    private(set) var hideDelays: [TimeInterval] = []

    func show() {}

    func updateTranscript(_ text: String) {
        transcripts.append(text)
    }

    func updateStatus(_ text: String) {
        statusMessages.append(text)
    }

    func updateAudioLevel(_ level: CGFloat) {}

    func hide(after delay: TimeInterval) {
        hideDelays.append(delay)
    }

    func hide() {
        hideDelays.append(0)
    }
}

@MainActor
private final class FakePasteInjector: PasteInjecting {
    private(set) var injectedTexts: [String] = []
    private let outcome: PasteInjectionOutcome

    init(outcome: PasteInjectionOutcome = PasteInjectionOutcome(clipboardWasRestored: true)) {
        self.outcome = outcome
    }

    func inject(text: String) async throws -> PasteInjectionOutcome {
        injectedTexts.append(text)
        return outcome
    }
}

@MainActor
private final class FakeLLMRefiner: LLMRefining {
    private let result: Result<String, Swift.Error>
    private let delayNanoseconds: UInt64

    init(result: Result<String, Swift.Error> = .success("refined text"), delayNanoseconds: UInt64 = 0) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func refine(_ text: String, baseURL: String, apiKey: String, model: String) async throws -> String {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        return try result.get()
    }
}

private enum FakeError: Swift.Error {
    case refineFailed
}
