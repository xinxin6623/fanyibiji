import Foundation
import AppKit

/// 剪贴板读写边界。抽象成协议便于单测注入桩，不在测试触碰系统剪贴板。
///
/// 取词策略：
///  - `ClipboardTextGrabber`：只读当前剪贴板兜底（不破坏用户剪贴板）。
///  - `SelectionTextGrabber`：模拟 ⌘C 取选中文字，取词后**还原**原剪贴板，
///    用 `changeCount` 判定复制是否真的产生新内容（兑现原 T08 推迟项）。
protocol PasteboardReading: Sendable {
    func readString() -> String?
    /// 系统剪贴板的变更计数。每次写入自增，用于判定模拟 ⌘C 是否生效。
    var changeCount: Int { get }
    /// 覆盖写入纯文本（用于取词后还原用户原剪贴板）。
    func writeString(_ value: String)
    /// 清空（原剪贴板本就为空时的还原路径）。
    func clearContents()
}

/// 生产实现：`NSPasteboard.general`。
struct SystemPasteboard: PasteboardReading {
    func readString() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    var changeCount: Int {
        NSPasteboard.general.changeCount
    }

    func writeString(_ value: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
    }

    func clearContents() {
        NSPasteboard.general.clearContents()
    }
}
