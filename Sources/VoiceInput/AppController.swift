import AppKit
import AVFoundation
import ApplicationServices
import Speech

final class AppController: NSObject {
    private let settings = AppSettings.shared
    private let fnKeyMonitor = FnKeyMonitor()
    private let transcriber = SpeechTranscriber()
    private let overlayController = RecordingOverlayController()
    private let pasteInjector = PasteInjector()
    private let llmRefiner = LLMRefiner()
    private let settingsWindowController = SettingsWindowController()

    private var statusItem: NSStatusItem?
    private var isRecording = false
    private var isFinalizing = false
    private var permissionsPrimed = false
    private var observer: NSObjectProtocol?
    private var eventTapAvailable = true

    func start() {
        configureStatusItem()
        configureCallbacks()
        requestInitialPermissions()
        eventTapAvailable = fnKeyMonitor.start()
        rebuildMenu()

        observer = NotificationCenter.default.addObserver(
            forName: .appSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.rebuildMenu()
        }
    }

    func stop() {
        fnKeyMonitor.stop()
        transcriber.cancel()

        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice Input")
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "Voice Input"
        statusItem = item
    }

    private func configureCallbacks() {
        fnKeyMonitor.onPressStateChanged = { [weak self] isPressed in
            guard let self else { return }

            if isPressed {
                self.beginRecording()
            } else {
                self.endRecording()
            }
        }

        transcriber.onLevelChanged = { [weak self] level in
            self?.overlayController.updateAudioLevel(level)
        }

        transcriber.onTranscriptChanged = { [weak self] transcript in
            self?.overlayController.updateTranscript(transcript)
        }
    }

    private func requestInitialPermissions() {
        guard !permissionsPrimed else { return }
        permissionsPrimed = true

        SFSpeechRecognizer.requestAuthorization { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func beginRecording() {
        guard !isRecording, !isFinalizing else { return }

        isRecording = true
        overlayController.show()
        overlayController.updateStatus("Listening...")
        overlayController.updateTranscript("")

        do {
            try transcriber.start(locale: settings.selectedLanguage.locale)
        } catch {
            isRecording = false
            overlayController.updateStatus("Speech unavailable")
            overlayController.hide(after: 0.9)
        }
    }

    private func endRecording() {
        guard isRecording, !isFinalizing else { return }

        isRecording = false
        isFinalizing = true
        overlayController.updateAudioLevel(0)

        Task { @MainActor [weak self] in
            guard let self else { return }

            let transcript = await self.transcriber.stop()
            let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmedTranscript.isEmpty else {
                self.overlayController.hide()
                self.isFinalizing = false
                return
            }

            var finalText = trimmedTranscript

            if self.settings.llmEnabled, self.settings.hasLLMConfiguration {
                self.overlayController.updateStatus("Refining...")

                do {
                    let refined = try await self.llmRefiner.refine(
                        trimmedTranscript,
                        baseURL: self.settings.apiBaseURL,
                        apiKey: self.settings.apiKey,
                        model: self.settings.model
                    )

                    let candidate = refined.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty {
                        finalText = candidate
                    }
                } catch {
                    self.overlayController.updateStatus("Refine failed")
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }

            self.overlayController.updateTranscript(finalText)

            do {
                try await self.pasteInjector.inject(text: finalText)
                self.overlayController.hide()
            } catch {
                self.overlayController.updateStatus("Paste failed")
                self.overlayController.hide(after: 1.0)
            }

            self.isFinalizing = false
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let titleItem = NSMenuItem(
            title: "Current language: \(settings.selectedLanguage.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        if !eventTapAvailable {
            let warningItem = NSMenuItem(
                title: "Fn listener unavailable (grant Input Monitoring)",
                action: nil,
                keyEquivalent: ""
            )
            warningItem.isEnabled = false
            menu.addItem(warningItem)
        }

        menu.addItem(.separator())

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
}
