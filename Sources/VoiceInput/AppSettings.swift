import Foundation

enum SpeechProvider: String, CaseIterable {
    case apple
    case openAI = "openai"

    var displayName: String {
        switch self {
        case .apple:
            return "Apple Speech"
        case .openAI:
            return "OpenAI"
        }
    }
}

enum AppLanguage: String, CaseIterable {
    case english = "en-US"
    case simplifiedChinese = "zh-CN"
    case traditionalChinese = "zh-TW"
    case japanese = "ja-JP"
    case korean = "ko-KR"

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        case .traditionalChinese:
            return "繁體中文"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        }
    }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var speechLanguageCode: String {
        rawValue.split(separator: "-").first.map(String.init) ?? rawValue
    }
}

extension Notification.Name {
    static let appSettingsDidChange = Notification.Name("AppSettingsDidChange")
}

final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let language = "selectedLanguage"
        static let speechProvider = "speech.provider"
        static let llmEnabled = "llmEnabled"
        static let apiBaseURL = "openai.apiBaseURL"
        static let apiKey = "openai.apiKey"
        static let speechModel = "speech.model"
        static let refinementModel = "llm.model"
    }

    private let defaults: UserDefaults

    private(set) var selectedLanguage: AppLanguage
    private(set) var speechProvider: SpeechProvider
    private(set) var llmEnabled: Bool
    private(set) var apiBaseURL: String
    private(set) var apiKey: String
    private(set) var speechModel: String
    private(set) var refinementModel: String

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedLanguage = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .simplifiedChinese
        speechProvider = SpeechProvider(rawValue: defaults.string(forKey: Keys.speechProvider) ?? "") ?? .apple
        llmEnabled = defaults.object(forKey: Keys.llmEnabled) as? Bool ?? false
        apiBaseURL = defaults.string(forKey: Keys.apiBaseURL) ?? ""
        apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        speechModel = defaults.string(forKey: Keys.speechModel) ?? "whisper-1"
        refinementModel = defaults.string(forKey: Keys.refinementModel) ?? ""
    }

    var hasLLMConfiguration: Bool {
        !apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !refinementModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasSpeechConfiguration: Bool {
        !apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !speechModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func updateLanguage(_ language: AppLanguage) {
        selectedLanguage = language
        defaults.set(language.rawValue, forKey: Keys.language)
        notifyChanged()
    }

    func updateSpeechProvider(_ provider: SpeechProvider) {
        speechProvider = provider
        defaults.set(provider.rawValue, forKey: Keys.speechProvider)
        notifyChanged()
    }

    func updateLLMEnabled(_ enabled: Bool) {
        llmEnabled = enabled
        defaults.set(enabled, forKey: Keys.llmEnabled)
        notifyChanged()
    }

    func saveAPIConfiguration(
        speechProvider: SpeechProvider,
        baseURL: String,
        apiKey: String,
        speechModel: String,
        refinementModel: String
    ) {
        let sanitizedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedSpeechModel = speechModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedRefinementModel = refinementModel.trimmingCharacters(in: .whitespacesAndNewlines)

        self.speechProvider = speechProvider
        self.apiBaseURL = sanitizedBaseURL
        self.apiKey = apiKey
        self.speechModel = sanitizedSpeechModel
        self.refinementModel = sanitizedRefinementModel

        defaults.set(speechProvider.rawValue, forKey: Keys.speechProvider)
        defaults.set(sanitizedBaseURL, forKey: Keys.apiBaseURL)
        defaults.set(apiKey, forKey: Keys.apiKey)
        defaults.set(sanitizedSpeechModel, forKey: Keys.speechModel)
        defaults.set(sanitizedRefinementModel, forKey: Keys.refinementModel)
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .appSettingsDidChange, object: self)
    }
}
