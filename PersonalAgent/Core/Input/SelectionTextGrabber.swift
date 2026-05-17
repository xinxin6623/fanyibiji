import Foundation

/// 模拟一次 ⌘C 的键盘事件合成边界。抽象成协议便于单测注入桩
/// （无法对真实 CGEvent 注入做确定性 headless 单测）。
protocol CopyKeystrokeSending: Sendable {
    /// 向当前焦点应用合成 ⌘C。需辅助功能权限（与全局热键同一权限）。
    func sendCopyKeystroke()
}

/// 划词取词：模拟 ⌘C 抓当前选中文字（对齐 Easydict 划词翻译）。
///
/// 流程（兑现原 T08 推迟的「模拟复制」）：
///   1. 记录原剪贴板内容 + `changeCount`；
///   2. 合成 ⌘C；
///   3. 轮询等待 `changeCount` 自增（最多 `timeout`，无选中则永不增）；
///   4. 成功 → 读出文本并**还原**原剪贴板；超时/空白 → 还原后
///      返回 `.invalidInput`（调用方静默不做事，对齐 Easydict 默认）。
///
/// 纯逻辑（轮询用注入的 `sleep`），可 headless 单测。
struct SelectionTextGrabber: Sendable {
    private let pasteboard: PasteboardReading
    private let keystroke: CopyKeystrokeSending
    private let timeout: Duration
    private let pollInterval: Duration
    private let sleep: @Sendable (Duration) async -> Void

    init(pasteboard: PasteboardReading,
         keystroke: CopyKeystrokeSending,
         timeout: Duration = .milliseconds(600),
         pollInterval: Duration = .milliseconds(20),
         sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.pasteboard = pasteboard
        self.keystroke = keystroke
        self.timeout = timeout
        self.pollInterval = pollInterval
        self.sleep = sleep
    }

    /// 成功返回去除首尾空白后的选中文本（保留内部换行）。
    /// 无选中（剪贴板未变更）/ 纯空白 → `.invalidInput`，原剪贴板已还原。
    func grab() async -> Result<String, AgentError> {
        let originalText = pasteboard.readString()
        let originalCount = pasteboard.changeCount

        keystroke.sendCopyKeystroke()

        let deadline = ContinuousClock.now.advanced(by: timeout)
        var updated = false
        while ContinuousClock.now < deadline {
            if pasteboard.changeCount != originalCount {
                updated = true
                break
            }
            await sleep(pollInterval)
        }

        guard updated else {
            // 无选中文字：剪贴板没动，原样不动，静默失败。
            return .failure(AgentError(category: .invalidInput,
                                       diagnosticMessage: "no text selected"))
        }

        let grabbed = pasteboard.readString()
        restoreClipboard(originalText)

        guard let raw = grabbed else {
            return .failure(AgentError(category: .invalidInput,
                                       diagnosticMessage: "selection not text"))
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(AgentError(category: .invalidInput,
                                       diagnosticMessage: "selection blank"))
        }
        return .success(trimmed)
    }

    /// 还原用户原剪贴板：原本有文本则写回，原本为空则清空。
    /// 不破坏用户剪贴板是硬约束（AGENTS）。
    private func restoreClipboard(_ original: String?) {
        if let original {
            pasteboard.writeString(original)
        } else {
            pasteboard.clearContents()
        }
    }
}
