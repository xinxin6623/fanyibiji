import SwiftUI
import AppKit

/// 快捷键录制控件：点击进入录制态，按下任意带 ⌘/⌃ 的组合键即捕获。
///
/// 用 NSViewRepresentable 接一个 first-responder NSView 拿 keyDown
/// （SwiftUI 无原生组合键捕获）。Esc 取消录制保持原值；非法组合
/// （无 ⌘/⌃）忽略，继续等待合法输入。
struct KeyRecorderField: NSViewRepresentable {
    @Binding var binding: KeyBinding
    @Binding var recording: Bool

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onCapture = { kb in
            binding = kb
            recording = false
        }
        v.onCancel = { recording = false }
        return v
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.isRecording = recording
        // 进入录制态后异步抢焦点：toggle 当帧 window/responder 链
        // 可能未就绪，放到下一轮 runloop 才稳定拿到 firstResponder。
        if recording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    /// 录制视图。关键点：
    ///  - 有真实非零 frame（0×0 无法成为 firstResponder）；
    ///  - 重写 `performKeyEquivalent` 拦截带 ⌘ 的组合键——否则
    ///    ⌘C/⌘⇧D 这类会被当菜单快捷键吞掉，永远到不了 `keyDown`，
    ///    这正是「录不到键」的根因；
    ///  - 录制态下吞掉事件返回 true，不让其继续传播触发副作用。
    final class RecorderView: NSView {
        var onCapture: ((KeyBinding) -> Void)?
        var onCancel: (() -> Void)?
        var isRecording = false

        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            // 录制态下，带修饰键的组合（含 ⌘）会先走 keyEquivalent，
            // 必须在这里截获并消费，阻止系统/菜单处理。
            guard isRecording else {
                return super.performKeyEquivalent(with: event)
            }
            return capture(event)
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { super.keyDown(with: event); return }
            _ = capture(event)
        }

        /// 处理一次按键：Esc 取消；合法组合（带 ⌘/⌃）捕获；
        /// 非法（无 ⌘/⌃）忽略并继续等待。返回是否已消费事件。
        private func capture(_ event: NSEvent) -> Bool {
            if event.keyCode == 53 { onCancel?(); return true } // Esc
            let mods = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
            let kb = KeyBinding(keyCode: event.keyCode,
                                modifiers: mods.rawValue)
            guard kb.isValid else { return true } // 吞掉但不捕获，继续等
            onCapture?(kb)
            return true
        }
    }
}

/// 快捷键设置面板（sheet 内容）。两组绑定各一个录制框，
/// 重复绑定时给出提示（截屏 OCR 优先，划词会失效）。
struct HotkeySettingsView: View {
    @EnvironmentObject private var controller: AppController
    @Environment(\.dismiss) private var dismiss

    @State private var translateSelection: KeyBinding
    @State private var captureOCR: KeyBinding
    @State private var recordingTranslate = false
    @State private var recordingCapture = false

    /// 密钥输入框的草稿值（key=Keychain account）。留空=不改动该项。
    @State private var secretDrafts: [String: String] = [:]
    /// 各密钥是否已配置（保存后刷新，驱动"已配置/未配置"标记）。
    @State private var secretStatus: [AppController.SecretField] = []
    /// 系统提示词草稿（编辑中，保存时写回）。
    @State private var systemPrompt: String

    init(config: HotkeyConfig, promptConfig: PromptConfig) {
        _translateSelection = State(initialValue: config.translateSelection)
        _captureOCR = State(initialValue: config.captureOCR)
        _systemPrompt = State(initialValue: promptConfig.systemPrompt)
    }

    private var hasConflict: Bool {
        translateSelection.keyCode == captureOCR.keyCode &&
        translateSelection.modifierFlags == captureOCR.modifierFlags
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("settings.hotkey.title")
                .font(.title2).fontWeight(.semibold)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    row(titleKey: "settings.hotkey.translate_selection",
                        hintKey: "settings.hotkey.translate_selection.hint",
                        binding: $translateSelection,
                        recording: $recordingTranslate)

                    row(titleKey: "settings.hotkey.capture_ocr",
                        hintKey: "settings.hotkey.capture_ocr.hint",
                        binding: $captureOCR,
                        recording: $recordingCapture)

                    if hasConflict {
                        Label("settings.hotkey.conflict",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Divider()
                    secretsSection

                    Divider()
                    promptSection
                }
            }
            Divider()

            HStack {
                Button("settings.hotkey.reset") {
                    translateSelection = .defaultTranslateSelection
                    captureOCR = .defaultCaptureOCR
                }
                Spacer()
                Button("settings.hotkey.cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                // 统一保存：快捷键 + 所有有草稿值的密钥一起存，
                // 一个按钮管全部，避免"以为存了其实没存"。
                Button("settings.hotkey.save") {
                    controller.updateHotkeyConfig(HotkeyConfig(
                        translateSelection: translateSelection,
                        captureOCR: captureOCR))
                    saveSecrets()
                    controller.updatePromptConfig(
                        PromptConfig(systemPrompt: systemPrompt))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(hasConflict)
            }
        }
        .padding(28)
        .frame(width: 480, height: 640)
    }

    /// 密钥配置区：4 个 SecureField。已配置项 placeholder 显示
    /// "已配置（留空不改）"，不回显明文。保存写 Keychain，ACL 自动
    /// 绑定当前签名——这是根治反复弹密码的正解。
    @ViewBuilder
    private var secretsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("settings.secret.title")
                .font(.headline)
            Text("settings.secret.hint")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(secretStatus) { field in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(LocalizedStringKey(field.titleKey))
                            .font(.subheadline)
                        if field.isSet {
                            Text("settings.secret.configured")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        } else {
                            Text("settings.secret.not_configured")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    SecureField(
                        field.isSet
                            ? String(localized: "settings.secret.placeholder_set")
                            : String(localized: "settings.secret.placeholder_empty"),
                        text: Binding(
                            get: { secretDrafts[field.id] ?? "" },
                            set: { secretDrafts[field.id] = $0 }))
                        .textFieldStyle(.roundedBorder)
                }
            }

            Text("settings.secret.save_note")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear { secretStatus = controller.secretFields() }
    }

    /// 只写有草稿值的项（留空=不动该项）。写完刷新状态、清草稿。
    private func saveSecrets() {
        for (key, value) in secretDrafts where
            !value.trimmingCharacters(in: .whitespaces).isEmpty {
            controller.saveSecret(value, forKey: key)
        }
        secretDrafts.removeAll()
        secretStatus = controller.secretFields()
    }

    /// 系统提示词编辑区。约束 LLM 查询行为（不影响翻译）。
    /// 留空保存时由 store sanitize 回默认，不会让 LLM 失约束。
    @ViewBuilder
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.prompt.title")
                .font(.headline)
            Text("settings.prompt.hint")
                .font(.caption).foregroundStyle(.secondary)

            TextEditor(text: $systemPrompt)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3)))

            Button("settings.prompt.reset") {
                systemPrompt = PromptConfig.defaultSystemPrompt
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func row(titleKey: LocalizedStringKey,
                     hintKey: LocalizedStringKey,
                     binding: Binding<KeyBinding>,
                     recording: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleKey).font(.headline)
            Text(hintKey).font(.caption).foregroundStyle(.secondary)
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(recording.wrappedValue
                                ? Color.accentColor : Color.secondary.opacity(0.4),
                                lineWidth: recording.wrappedValue ? 2 : 1)
                        .frame(height: 32)
                    Text(recording.wrappedValue
                         ? String(localized: "settings.hotkey.press_keys")
                         : binding.wrappedValue.displayString)
                        .font(.body.monospaced())
                    // 铺满录制框（0×0 无法成为 firstResponder）。
                    KeyRecorderField(binding: binding, recording: recording)
                        .frame(height: 32)
                        .allowsHitTesting(false)
                }
                Button(recording.wrappedValue
                       ? "settings.hotkey.recording"
                       : "settings.hotkey.record") {
                    recording.wrappedValue.toggle()
                }
            }
        }
    }
}
