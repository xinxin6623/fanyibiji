import Foundation
import AppKit

/// 单个快捷键绑定（纯值类型，可落 JSON）。
///
/// `keyCode` 为虚拟键码（与 `NSEvent.keyCode` 一致，布局无关），
/// `modifiers` 存 `NSEvent.ModifierFlags` 的 rawValue（仅保留
/// device-independent 部分）。用键码而非字符，避免输入法/布局漂移。
struct KeyBinding: Codable, Sendable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt

    /// 显式 CodingKeys：固定 snake_case 字面量，绕开
    /// `.convertFromSnakeCase` 对首字母缩写不对称的坑
    /// （参考 `ProviderConfig`/`TTSConfig` 同类注释）。
    enum CodingKeys: String, CodingKey {
        case keyCode = "key_code"
        case modifiers
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
            .intersection(.deviceIndependentFlagsMask)
    }

    /// 是否为合法可用绑定：必须带 ⌘ 或 ⌃（纯字母键做全局热键会误触发）。
    var isValid: Bool {
        let m = modifierFlags
        return m.contains(.command) || m.contains(.control)
    }

    /// 人类可读形式，如 `⌘⇧D`，用于设置界面展示。
    var displayString: String {
        var s = ""
        let m = modifierFlags
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        s += KeyBinding.keyName(keyCode)
        return s
    }

    /// 常见键码 → 显示名（覆盖字母/数字够用；其它退化为 key#码）。
    static func keyName(_ code: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
            26: "7", 28: "8", 25: "9", 29: "0",
            43: ",", 47: ".", 44: "/", 27: "-", 24: "=",
            33: "[", 30: "]", 41: ";", 39: "'", 42: "\\", 50: "`",
            49: "Space", 36: "↩", 48: "⇥", 53: "⎋"
        ]
        return map[code] ?? "key\(code)"
    }
}

/// 两组可配置快捷键 + 持久化值类型。
///
/// 默认：截屏 OCR = ⌘⇧D（保持历史默认不变，避免破坏既有肌肉记忆）；
/// 划词翻译 = ⌘⇧C（对齐 Easydict 习惯，⌘⇧C 不与系统常用项冲突）。
/// 编码 snake_case，与其它 store 一致。容错回默认由 store 负责。
struct HotkeyConfig: Codable, Sendable, Equatable {
    /// 划词翻译（模拟 ⌘C 取选中文字 → 翻译）。
    var translateSelection: KeyBinding
    /// 截屏 OCR 取词（框选 → 截图 → OCR → 翻译）。
    var captureOCR: KeyBinding
    /// 划词进草稿（模拟 ⌘C 取选中文字 → 原文直接追加到当前草稿 Tab）。
    /// 不走翻译/LLM，纯摘录沉淀；按 James 决策插入原文并把主窗口调前台。
    var selectionToNote: KeyBinding

    /// 显式 CodingKeys：`captureOCR` 自动 snake_case 编码为
    /// `capture_ocr`、但 `.convertFromSnakeCase` 会还原成 `captureOcr`
    /// 致解码 keyNotFound。固定字面量绕开此不对称。
    /// 旧配置无 `selection_to_note` 字段：解码缺省回默认（见下方 init
    /// + decoder 容错）。
    enum CodingKeys: String, CodingKey {
        case translateSelection = "translate_selection"
        case captureOCR = "capture_ocr"
        case selectionToNote = "selection_to_note"
    }

    init(translateSelection: KeyBinding = .defaultTranslateSelection,
         captureOCR: KeyBinding = .defaultCaptureOCR,
         selectionToNote: KeyBinding = .defaultSelectionToNote) {
        self.translateSelection = translateSelection
        self.captureOCR = captureOCR
        self.selectionToNote = selectionToNote
    }

    /// 自定义 decoder：`selection_to_note` 是后加字段，旧落盘文件没有
    /// 它——`decodeIfPresent` 缺省回默认，避免老用户升级后解码
    /// keyNotFound 直接丢失全部快捷键配置。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        translateSelection = try c.decode(
            KeyBinding.self, forKey: .translateSelection)
        captureOCR = try c.decode(KeyBinding.self, forKey: .captureOCR)
        selectionToNote = try c.decodeIfPresent(
            KeyBinding.self, forKey: .selectionToNote)
            ?? .defaultSelectionToNote
    }
}

extension KeyBinding {
    /// ⌘⇧C —— keyCode 8 = 'C'。
    static let defaultTranslateSelection = KeyBinding(
        keyCode: 8,
        modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue)

    /// ⌘⇧D —— keyCode 2 = 'D'（与历史 GlobalHotkeyMonitor 默认一致）。
    static let defaultCaptureOCR = KeyBinding(
        keyCode: 2,
        modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue)

    /// ⌘⇧. —— keyCode 47 = '.'（与 ⌘⇧C/⌘⇧D 错开，避免冲突）。
    static let defaultSelectionToNote = KeyBinding(
        keyCode: 47,
        modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue)
}
