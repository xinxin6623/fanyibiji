import Foundation

/// 翻译目标语言。源语言始终 `auto`（FreeWebTranslateProvider 已 sl=auto），
/// 只需配置目标。每项带：
///  - `code`：翻译 provider 的 `tl` 语言代码（经 languageHints 传入）
///  - `naturalName`：LLM prompt 用的自然语言名（截屏 LLM 翻译路径）
///  - `flag` / `displayName`：UI 语言方向条展示
enum TargetLanguage: String, Codable, Sendable, CaseIterable {
    case chinese
    case english
    case japanese
    case korean
    case french
    case german
    case spanish

    /// 翻译 provider `tl` 代码（保持与原写死值 "zh" 兼容）。
    var code: String {
        switch self {
        case .chinese:  return "zh"
        case .english:  return "en"
        case .japanese: return "ja"
        case .korean:   return "ko"
        case .french:   return "fr"
        case .german:   return "de"
        case .spanish:  return "es"
        }
    }

    /// LLM prompt 用的自然语言名（与原写死 "中文" 兼容）。
    var naturalName: String {
        switch self {
        case .chinese:  return "中文"
        case .english:  return "English"
        case .japanese: return "日本語"
        case .korean:   return "한국어"
        case .french:   return "Français"
        case .german:   return "Deutsch"
        case .spanish:  return "Español"
        }
    }

    var flag: String {
        switch self {
        case .chinese:  return "🇨🇳"
        case .english:  return "🇬🇧"
        case .japanese: return "🇯🇵"
        case .korean:   return "🇰🇷"
        case .french:   return "🇫🇷"
        case .german:   return "🇩🇪"
        case .spanish:  return "🇪🇸"
        }
    }

    /// UI 展示名（带旗帜），如 `🇨🇳 简体中文`。本地化键见 xcstrings。
    var displayNameKey: String { "lang.\(rawValue)" }
}

/// 语言配置（纯值类型，可落 JSON）。源语言固定 auto，只持久化目标。
/// 显式 snake_case CodingKeys，避开 .convertFromSnakeCase 缩写不对称坑
/// （与 HotkeyConfig/PromptConfig 同教训）。
struct LanguageConfig: Codable, Sendable, Equatable {
    var target: TargetLanguage

    enum CodingKeys: String, CodingKey {
        case target
    }

    init(target: TargetLanguage = .chinese) {
        self.target = target
    }
}
