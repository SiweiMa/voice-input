import Foundation

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
}

extension Notification.Name {
    static let appSettingsDidChange = Notification.Name("AppSettingsDidChange")
}

final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let language = "selectedLanguage"
        static let llmEnabled = "llmEnabled"
        static let apiBaseURL = "llm.apiBaseURL"
        static let apiKey = "llm.apiKey"
        static let model = "llm.model"
    }

    private let defaults: UserDefaults

    private(set) var selectedLanguage: AppLanguage
    private(set) var llmEnabled: Bool
    private(set) var apiBaseURL: String
    private(set) var apiKey: String
    private(set) var model: String

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedLanguage = AppLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .simplifiedChinese
        llmEnabled = defaults.object(forKey: Keys.llmEnabled) as? Bool ?? false
        apiBaseURL = defaults.string(forKey: Keys.apiBaseURL) ?? ""
        apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        model = defaults.string(forKey: Keys.model) ?? ""
    }

    var hasLLMConfiguration: Bool {
        !apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func updateLanguage(_ language: AppLanguage) {
        selectedLanguage = language
        defaults.set(language.rawValue, forKey: Keys.language)
        notifyChanged()
    }

    func updateLLMEnabled(_ enabled: Bool) {
        llmEnabled = enabled
        defaults.set(enabled, forKey: Keys.llmEnabled)
        notifyChanged()
    }

    func saveLLMConfiguration(baseURL: String, apiKey: String, model: String) {
        let sanitizedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        self.apiBaseURL = sanitizedBaseURL
        self.apiKey = apiKey
        self.model = sanitizedModel

        defaults.set(sanitizedBaseURL, forKey: Keys.apiBaseURL)
        defaults.set(apiKey, forKey: Keys.apiKey)
        defaults.set(sanitizedModel, forKey: Keys.model)
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .appSettingsDidChange, object: self)
    }
}
