import AppKit
import AVFoundation
import ApplicationServices
import Speech

@MainActor
final class AppController: NSObject {
    // Session lifecycle:
    // idle -> recording -> finalizing -> idle
    //          ^ stop/cancel ----------|
    private enum SessionState {
        case idle
        case recording(sessionID: Int)
        case finalizing(sessionID: Int)
    }

    private let settings: AppSettingsStore
    private let fnKeyMonitor: FnKeyMonitoring
    private let transcriber: SpeechTranscribing
    private let overlayController: OverlayControlling
    private let pasteInjector: PasteInjecting
    private let llmRefiner: LLMRefining
    private let settingsWindowController = SettingsWindowController()

    private var statusItem: NSStatusItem?
    private var sessionState: SessionState = .idle
    private var nextSessionID = 0
    private var microphonePermissionPrimed = false
    private var speechPermissionPrimed = false
    private var observer: NSObjectProtocol?
    private var eventTapAvailable = true
    private var fnMonitorRetryTimer: Timer?
    private var finalizationTask: Task<Void, Never>?

    override init() {
        settings = AppSettings.shared
        fnKeyMonitor = FnKeyMonitor()
        transcriber = SpeechTranscriber()
        overlayController = RecordingOverlayController()
        pasteInjector = PasteInjector()
        llmRefiner = LLMRefiner()
        super.init()
    }

    init(
        settings: AppSettingsStore,
        fnKeyMonitor: FnKeyMonitoring,
        transcriber: SpeechTranscribing,
        overlayController: OverlayControlling,
        pasteInjector: PasteInjecting,
        llmRefiner: LLMRefining
    ) {
        self.settings = settings
        self.fnKeyMonitor = fnKeyMonitor
        self.transcriber = transcriber
        self.overlayController = overlayController
        self.pasteInjector = pasteInjector
        self.llmRefiner = llmRefiner
        super.init()
    }

    func start() {
        configureStatusItem()
        configureCallbacks()
        requestInitialPermissions()
        refreshFnMonitorAvailability()
        rebuildMenu()

        observer = NotificationCenter.default.addObserver(
            forName: .appSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.primeSpeechPermissionIfNeeded()
                self?.rebuildMenu()
            }
        }
    }

    func stop() {
        fnMonitorRetryTimer?.invalidate()
        finalizationTask?.cancel()
        finalizationTask = nil
        sessionState = .idle
        fnKeyMonitor.stop()
        transcriber.cancel()
        overlayController.hide()

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = AppBrand.statusBarImage()
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "Voice Input"
        statusItem = item
    }

    private func configureCallbacks() {
        fnKeyMonitor.onPressStateChanged = { [weak self] isPressed in
            self?.handlePressStateChanged(isPressed)
        }

        transcriber.onLevelChanged = { [weak self] level in
            self?.overlayController.updateAudioLevel(level)
        }

        transcriber.onTranscriptChanged = { [weak self] transcript in
            self?.overlayController.updateTranscript(transcript)
        }
    }

    private func requestInitialPermissions() {
        primeMicrophonePermissionIfNeeded()
        primeSpeechPermissionIfNeeded()

        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func primeMicrophonePermissionIfNeeded() {
        guard !microphonePermissionPrimed else { return }
        microphonePermissionPrimed = true
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    private func primeSpeechPermissionIfNeeded() {
        guard settings.speechProvider == .apple, !speechPermissionPrimed else { return }
        speechPermissionPrimed = true
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    private func refreshFnMonitorAvailability() {
        let wasAvailable = eventTapAvailable
        eventTapAvailable = fnKeyMonitor.start()

        if eventTapAvailable {
            fnMonitorRetryTimer?.invalidate()
            fnMonitorRetryTimer = nil
        } else if fnMonitorRetryTimer == nil {
            fnMonitorRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let becameAvailable = self.fnKeyMonitor.start()
                    guard becameAvailable else { return }

                    self.eventTapAvailable = true
                    self.fnMonitorRetryTimer?.invalidate()
                    self.fnMonitorRetryTimer = nil
                    self.rebuildMenu()
                }
            }
        }

        if wasAvailable != eventTapAvailable {
            rebuildMenu()
        }
    }

    private func beginRecording() {
        guard case .idle = sessionState else { return }

        let sessionID = makeSessionID()
        sessionState = .recording(sessionID: sessionID)
        overlayController.show()
        overlayController.updateStatus("Listening...")
        overlayController.updateTranscript("")

        do {
            try transcriber.start(
                provider: settings.speechProvider,
                locale: settings.selectedLanguage.locale,
                languageCode: settings.selectedLanguage.speechLanguageCode,
                apiBaseURL: settings.apiBaseURL,
                apiKey: settings.apiKey,
                model: settings.speechModel
            )
        } catch {
            sessionState = .idle
            overlayController.updateStatus(displayMessage(for: error))
            overlayController.hide(after: 1.2)
        }
    }

    private func endRecording() {
        guard case let .recording(sessionID) = sessionState else { return }

        sessionState = .finalizing(sessionID: sessionID)
        overlayController.updateAudioLevel(0)
        overlayController.updateStatus("Transcribing...")

        finalizationTask?.cancel()
        finalizationTask = Task { @MainActor [weak self] in
            await self?.finalizeRecording(sessionID: sessionID)
        }
    }

    private func rebuildMenu() {
        refreshFnMonitorAvailabilityIfNeeded()
        let menu = NSMenu()

        let titleItem = NSMenuItem(
            title: "Current language: \(settings.selectedLanguage.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        for warning in permissionWarnings() {
            let warningItem = NSMenuItem(title: warning, action: nil, keyEquivalent: "")
            warningItem.isEnabled = false
            menu.addItem(warningItem)
        }

        if menu.items.count > 1 {
            menu.addItem(.separator())
        }

        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for language in AppLanguage.allCases {
            let item = NSMenuItem(
                title: language.displayName,
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language.rawValue
            item.state = language == settings.selectedLanguage ? .on : .off
            languageMenu.addItem(item)
        }
        menu.setSubmenu(languageMenu, for: languageItem)
        menu.addItem(languageItem)

        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        let llmMenu = NSMenu()

        let toggleItem = NSMenuItem(
            title: settings.llmEnabled ? "Disable" : "Enable",
            action: #selector(toggleLLM(_:)),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = settings.llmEnabled ? .on : .off
        llmMenu.addItem(toggleItem)

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        llmMenu.addItem(settingsItem)

        menu.setSubmenu(llmMenu, for: llmItem)
        menu.addItem(llmItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit VoiceInput", action: #selector(quit(_:)), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let language = AppLanguage(rawValue: rawValue)
        else {
            return
        }

        settings.updateLanguage(language)
    }

    @objc private func toggleLLM(_ sender: NSMenuItem) {
        settings.updateLLMEnabled(!settings.llmEnabled)
    }

    @objc private func openSettings(_ sender: Any?) {
        settingsWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func refreshFnMonitorAvailabilityIfNeeded() {
        guard !eventTapAvailable else { return }
        refreshFnMonitorAvailability()
    }

    func handlePressStateChanged(_ isPressed: Bool) {
        if isPressed {
            beginRecording()
        } else {
            endRecording()
        }
    }

    private func makeSessionID() -> Int {
        nextSessionID += 1
        return nextSessionID
    }

    private func isFinalizingSession(_ sessionID: Int) -> Bool {
        guard case let .finalizing(currentID) = sessionState else {
            return false
        }

        return currentID == sessionID
    }

    private func completeFinalization(sessionID: Int) {
        if case let .finalizing(currentID) = sessionState, currentID == sessionID {
            sessionState = .idle
        }

        if case .idle = sessionState {
            finalizationTask = nil
        }
    }

    private func finalizeRecording(sessionID: Int) async {
        let transcript: String
        do {
            transcript = try await transcriber.stop()
            guard isFinalizingSession(sessionID), !Task.isCancelled else {
                completeFinalization(sessionID: sessionID)
                return
            }
        } catch is CancellationError {
            completeFinalization(sessionID: sessionID)
            return
        } catch {
            overlayController.updateStatus(displayMessage(for: error))
            overlayController.hide(after: 1.0)
            completeFinalization(sessionID: sessionID)
            return
        }

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            overlayController.hide()
            completeFinalization(sessionID: sessionID)
            return
        }

        var finalText = trimmedTranscript

        if settings.llmEnabled, settings.hasLLMConfiguration {
            overlayController.updateStatus("Refining...")

            do {
                let refined = try await llmRefiner.refine(
                    trimmedTranscript,
                    baseURL: settings.apiBaseURL,
                    apiKey: settings.apiKey,
                    model: settings.refinementModel
                )

                guard isFinalizingSession(sessionID), !Task.isCancelled else {
                    completeFinalization(sessionID: sessionID)
                    return
                }

                let candidate = refined.trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    finalText = candidate
                }
            } catch is CancellationError {
                completeFinalization(sessionID: sessionID)
                return
            } catch {
                overlayController.updateStatus("Refine failed")
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }

        guard isFinalizingSession(sessionID), !Task.isCancelled else {
            completeFinalization(sessionID: sessionID)
            return
        }

        overlayController.updateTranscript(finalText)

        do {
            let outcome = try await pasteInjector.inject(text: finalText)
            guard isFinalizingSession(sessionID), !Task.isCancelled else {
                completeFinalization(sessionID: sessionID)
                return
            }

            if let message = outcome.statusMessage {
                overlayController.updateStatus(message)
                overlayController.hide(after: 1.0)
            } else {
                overlayController.hide()
            }
        } catch is CancellationError {
            completeFinalization(sessionID: sessionID)
            return
        } catch {
            overlayController.updateStatus("Paste failed")
            overlayController.hide(after: 1.0)
        }

        completeFinalization(sessionID: sessionID)
    }

    private func permissionWarnings() -> [String] {
        var warnings: [String] = []

        if !eventTapAvailable {
            warnings.append("Fn listener unavailable: allow Input Monitoring, then relaunch")
        }

        if !AXIsProcessTrusted() {
            warnings.append("Paste injection unavailable: allow Accessibility")
        }

        if settings.speechProvider == .openAI, !settings.hasSpeechConfiguration {
            warnings.append("OpenAI API settings are required for transcription")
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            warnings.append("Microphone permission is pending")
        default:
            warnings.append("Microphone permission is required")
        }

        if settings.speechProvider == .apple {
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized:
                break
            case .notDetermined:
                warnings.append("Speech Recognition permission is pending")
            default:
                warnings.append("Speech Recognition permission is required")
            }
        }

        return warnings
    }

    private func displayMessage(for error: Swift.Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }

        return "Transcription unavailable"
    }
}
