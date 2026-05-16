import Foundation

/// 剪贴板取词：读当前剪贴板文本，空/纯空白→`AgentError(.invalidInput)`，
/// 确保"取词失败不触发空查询"（AGENTS）。纯逻辑、可 headless 单测。
struct ClipboardTextGrabber: Sendable {
    private let pasteboard: PasteboardReading

    init(pasteboard: PasteboardReading) {
        self.pasteboard = pasteboard
    }

    /// 成功返回去除首尾空白后的文本（保留内部换行）。
    func grab() -> Result<String, AgentError> {
        guard let raw = pasteboard.readString() else {
            return .failure(AgentError(category: .invalidInput,
                                       diagnosticMessage: "clipboard empty"))
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(AgentError(category: .invalidInput,
                                       diagnosticMessage: "clipboard blank"))
        }
        return .success(trimmed)
    }
}
