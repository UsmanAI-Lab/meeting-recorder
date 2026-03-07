import Foundation

// MARK: - AppSettings

/// Central place for UserDefaults keys and default values.
struct AppSettings {

    enum Keys {
        static let openAIAPIKey = "openai_api_key"
        static let transcriptionLanguage = "transcription_language"
        static let autoLaunchOnLogin = "auto_launch_on_login"
        static let deleteAudioAfterTranscription = "delete_audio_after_transcription"
        static let launchCount = "launch_count"
    }

    static var openAIAPIKey: String {
        get { UserDefaults.standard.string(forKey: Keys.openAIAPIKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.openAIAPIKey) }
    }

    static var transcriptionLanguage: String {
        get { UserDefaults.standard.string(forKey: Keys.transcriptionLanguage) ?? "en" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.transcriptionLanguage) }
    }

    static var isConfigured: Bool {
        !openAIAPIKey.isEmpty
    }
}
