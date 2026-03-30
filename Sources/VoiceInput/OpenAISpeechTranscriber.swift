import AVFoundation
import Foundation

@MainActor
final class OpenAISpeechTranscriber: NSObject, SpeechBackendTranscribing {
    enum Error: Swift.Error, LocalizedError {
        case microphonePermissionDenied
        case missingAPIConfiguration
        case invalidBaseURL
        case recordingFailed
        case transcriptionFailed(statusCode: Int, body: String)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone permission is required."
            case .missingAPIConfiguration:
                return "Configure API Base URL, API Key, and Speech Model first."
            case .invalidBaseURL:
                return "The API Base URL is invalid."
            case .recordingFailed:
                return "Could not start audio recording."
            case let .transcriptionFailed(statusCode, body):
                return "Transcription failed (\(statusCode)): \(body)"
            case .emptyResponse:
                return "The transcription response was empty."
            }
        }
    }

    var onTranscriptChanged: ((String) -> Void)?
    var onLevelChanged: ((CGFloat) -> Void)?

    private var recorder: AVAudioRecorder?
    private var levelTimer: Timer?
    private var audioFileURL: URL?
    private var sessionConfiguration: OpenAISessionConfiguration?

    func start(locale: Locale, languageCode: String, apiBaseURL: String, apiKey: String, model: String) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw Error.microphonePermissionDenied
        }

        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty, !trimmedModel.isEmpty else {
            throw Error.missingAPIConfiguration
        }

        let endpoint = try transcriptionsURL(from: apiBaseURL)

        cancel()
        onTranscriptChanged?("")
        onLevelChanged?(0)

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            throw Error.recordingFailed
        }

        self.recorder = recorder
        audioFileURL = fileURL
        sessionConfiguration = OpenAISessionConfiguration(
            endpoint: endpoint,
            apiKey: trimmedAPIKey,
            model: trimmedModel,
            languageCode: normalizedLanguageCode(from: languageCode, locale: locale)
        )

        startLevelUpdates()
    }

    func stop() async throws -> String {
        stopLevelUpdates()
        onLevelChanged?(0)

        guard let recorder, let fileURL = audioFileURL, let sessionConfiguration else {
            return ""
        }

        recorder.stop()
        self.recorder = nil
        audioFileURL = nil
        self.sessionConfiguration = nil

        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        return try await transcribeAudio(at: fileURL, configuration: sessionConfiguration)
    }

    func cancel() {
        stopLevelUpdates()

        recorder?.stop()
        recorder = nil

        if let audioFileURL {
            try? FileManager.default.removeItem(at: audioFileURL)
        }

        audioFileURL = nil
        sessionConfiguration = nil
        onLevelChanged?(0)
    }

    private func startLevelUpdates() {
        stopLevelUpdates()

        levelTimer = Timer.scheduledTimer(
            timeInterval: 0.05,
            target: self,
            selector: #selector(updateMeterLevel),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopLevelUpdates() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    @objc private func updateMeterLevel() {
        recorder?.updateMeters()

        guard let averagePower = recorder?.averagePower(forChannel: 0) else { return }
        let decibels = max(-50, CGFloat(averagePower))
        let normalized = (decibels + 50) / 50
        onLevelChanged?(normalized)
    }

    private func transcribeAudio(at fileURL: URL, configuration: OpenAISessionConfiguration) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.addValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let audioData = try Data(contentsOf: fileURL)
        request.httpBody = MultipartFormData(boundary: boundary)
            .addField(named: "model", value: configuration.model)
            .addField(named: "language", value: configuration.languageCode)
            .addField(named: "response_format", value: "json")
            .addFile(
                named: "file",
                filename: fileURL.lastPathComponent,
                mimeType: "audio/mp4",
                data: audioData
            )
            .build()

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw Error.emptyResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw Error.transcriptionFailed(statusCode: httpResponse.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw Error.emptyResponse
        }

        return text
    }

    private func transcriptionsURL(from baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsedURL = URL(string: trimmed) else {
            throw Error.invalidBaseURL
        }

        if parsedURL.path.hasSuffix("/audio/transcriptions") {
            return parsedURL
        }

        guard var components = URLComponents(url: parsedURL, resolvingAgainstBaseURL: false) else {
            throw Error.invalidBaseURL
        }

        var path = components.path
        if path.hasSuffix("/") {
            path.removeLast()
        }
        path += "/audio/transcriptions"
        components.path = path

        guard let endpoint = components.url else {
            throw Error.invalidBaseURL
        }

        return endpoint
    }

    private func normalizedLanguageCode(from languageCode: String, locale: Locale) -> String {
        let trimmed = languageCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        return locale.identifier.split(separator: "-").first.map(String.init) ?? locale.identifier
    }
}

private struct OpenAISessionConfiguration {
    let endpoint: URL
    let apiKey: String
    let model: String
    let languageCode: String
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

private struct MultipartFormData {
    private let boundary: String
    private var body = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func addField(named name: String, value: String) -> MultipartFormData {
        var copy = self
        copy.body.appendString("--\(boundary)\r\n")
        copy.body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        copy.body.appendString("\(value)\r\n")
        return copy
    }

    func addFile(named name: String, filename: String, mimeType: String, data: Data) -> MultipartFormData {
        var copy = self
        copy.body.appendString("--\(boundary)\r\n")
        copy.body.appendString(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
        )
        copy.body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        copy.body.append(data)
        copy.body.appendString("\r\n")
        return copy
    }

    func build() -> Data {
        var result = body
        result.appendString("--\(boundary)--\r\n")
        return result
    }
}

private extension Data {
    mutating func appendString(_ value: String) {
        append(Data(value.utf8))
    }
}
