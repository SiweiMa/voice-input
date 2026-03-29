import AVFoundation
import Foundation
import Speech

final class SpeechTranscriber: @unchecked Sendable {
    enum Error: Swift.Error {
        case microphonePermissionDenied
        case speechPermissionDenied
        case recognizerUnavailable
    }

    var onTranscriptChanged: ((String) -> Void)?
    var onLevelChanged: ((CGFloat) -> Void)?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var latestTranscript = ""
    private var finishContinuation: CheckedContinuation<String, Never>?

    func start(locale: Locale) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw Error.microphonePermissionDenied
        }

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw Error.speechPermissionDenied
        }

        cancel()

        latestTranscript = ""
        onTranscriptChanged?("")
        onLevelChanged?(0)

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw Error.recognizerUnavailable
        }

        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        if #available(macOS 13.0, *) {
            request.addsPunctuation = false
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self, weak request] buffer, _ in
            guard let self, let request else { return }
            self.handleAudioBuffer(buffer, request: request)
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
            guard let self else { return }

            if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                self.latestTranscript = text
                DispatchQueue.main.async { [weak self] in
                    self?.onTranscriptChanged?(text)
                }
            }

            if result?.isFinal == true {
                self.finishIfNeeded(with: self.latestTranscript)
            }
        }

        audioEngine = engine
        recognitionRequest = request

        engine.prepare()
        try engine.start()
    }

    func stop() async -> String {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()

        return await withCheckedContinuation { continuation in
            finishContinuation = continuation

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                self.finishIfNeeded(with: self.latestTranscript)
            }
        }
    }

    func cancel() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }

        audioEngine = nil
        recognizer = nil

        finishIfNeeded(with: latestTranscript)
        latestTranscript = ""
    }

    private func finishIfNeeded(with text: String) {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine = nil
        recognizer = nil

        finishContinuation?.resume(returning: text)
        finishContinuation = nil
    }

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer, request: SFSpeechAudioBufferRecognitionRequest) {
        request.append(buffer)

        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let samples = channelData[0]
        var sum: Float = 0
        for index in 0..<frameLength {
            let value = samples[index]
            sum += value * value
        }

        let rms = sqrt(sum / Float(frameLength))
        let decibels = max(-50, 20 * log10(max(rms, 0.000_01)))
        let normalized = CGFloat((decibels + 50) / 50)

        DispatchQueue.main.async { [weak self] in
            self?.onLevelChanged?(normalized)
        }
    }
}
