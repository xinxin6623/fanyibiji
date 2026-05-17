import Foundation

/// LLM 查询的系统提示词配置（纯值类型，可落 JSON）。
///
/// 只约束 **LLM 查询**（`provider.complete`），不影响翻译路径
/// （翻译走 `translateProvider`，与系统提示词无关）。用户可在设置
/// 界面修改，留空则回默认（不会让 LLM 退化成无约束闲聊）。
///
/// 编码用显式 `CodingKeys`（snake_case 字面量），避免
/// `.convertFromSnakeCase` 对缩写的不对称坑（与 HotkeyConfig 同教训）。
struct PromptConfig: Codable, Sendable, Equatable {
    var systemPrompt: String

    enum CodingKeys: String, CodingKey {
        case systemPrompt = "system_prompt"
    }

    init(systemPrompt: String = PromptConfig.defaultSystemPrompt) {
        self.systemPrompt = systemPrompt
    }

    /// 默认系统提示词（James 确认：简洁助手、中文优先）。
    /// 约束 LLM 不闲聊、不复述问题、直接给结论。
    static let defaultSystemPrompt = """
    你是一个简洁、准确的助手。请遵守：
    - 用中文回答（除非用户明确要求其它语言）。
    - 直接给出结论或答案，不寒暄、不复述问题、不展开无关内容。
    - 若是词/句，解释其含义、用法，必要时给简短例句。
    - 不确定时直说不确定，不编造。
    """
}
