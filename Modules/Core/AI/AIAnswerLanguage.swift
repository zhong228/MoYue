import Foundation

/// A language the AI writes in: the language of a 查詞 answer, or the target of a translation.
///
/// The display name comes from the system, so it follows the interface language without a
/// string table; the prompt name is what the model is told, and is never shown.
enum AIAnswerLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case traditionalChinese = "zh-Hant"
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"
    case russian = "ru"

    var id: String { rawValue }

    /// The interface language, which is also the default answer and translation language.
    static var current: AIAnswerLanguage { matching(Bundle.main.preferredLocalizations.first) }

    static func matching(_ identifier: String?) -> AIAnswerLanguage {
        guard let identifier else { return .english }
        if let exact = AIAnswerLanguage(rawValue: identifier) { return exact }
        let lowered = identifier.lowercased()
        if lowered.hasPrefix("zh") {
            // zh-TW, zh-HK and zh-MO are written in traditional characters.
            let traditional = ["hant", "tw", "hk", "mo"].contains { lowered.contains($0) }
            return traditional ? .traditionalChinese : .simplifiedChinese
        }
        let base = String(lowered.prefix { $0 != "-" && $0 != "_" })
        return AIAnswerLanguage.allCases.first { $0.rawValue == base } ?? .english
    }

    var displayName: String {
        Locale.current.localizedString(forIdentifier: rawValue) ?? rawValue
    }

    var promptName: String {
        switch self {
        case .traditionalChinese: return "繁體中文"
        case .simplifiedChinese: return "簡體中文"
        case .english: return "英文"
        case .japanese: return "日文"
        case .korean: return "韓文"
        case .french: return "法文"
        case .german: return "德文"
        case .spanish: return "西班牙文"
        case .russian: return "俄文"
        }
    }
}
