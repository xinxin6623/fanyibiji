import SwiftUI
import AppKit

/// 快捷键录制控件：点击进入录制态，按下任意带 ⌘/⌃ 的组合键即捕获。
///
/// 关键点：带 ⌘ 的组合走 `performKeyEquivalent` 而非 `keyDown`，
/// 只重写 keyDown 会被菜单吞掉录不到——必须重写 performKeyEquivalent
/// 在录制态截获消费。0×0 视图无法成 firstResponder（要真实 frame +
/// allowsHitTesting(false)）；makeFirstResponder 要 async 延后。
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
        if recording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class RecorderView: NSView {
        var onCapture: ((KeyBinding) -> Void)?
        var onCancel: (() -> Void)?
        var isRecording = false

        override var acceptsFirstResponder: Bool { true }
        override var canBecomeKeyView: Bool { true }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording else {
                return super.performKeyEquivalent(with: event)
            }
            return capture(event)
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { super.keyDown(with: event); return }
            _ = capture(event)
        }

        private func capture(_ event: NSEvent) -> Bool {
            if event.keyCode == 53 { onCancel?(); return true } // Esc
            let mods = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
            let kb = KeyBinding(keyCode: event.keyCode,
                                modifiers: mods.rawValue)
            guard kb.isValid else { return true }
            onCapture?(kb)
            return true
        }
    }
}

/// 设置面板：macOS 标准顶部 Tab + 每页分组列表（对齐 Easydict 设置）。
/// 四个 Tab：通用(语言) / 快捷键 / 密钥 / 提示词。底部统一保存。
struct HotkeySettingsView: View {
    @EnvironmentObject private var controller: AppController
    @Environment(\.dismiss) private var dismiss

    private enum Tab: String, CaseIterable {
        case general, hotkey, secret, prompt, tts
        var titleKey: String {
            switch self {
            case .general: return "settings.tab.general"
            case .hotkey:  return "settings.tab.hotkey"
            case .secret:  return "settings.tab.secret"
            case .prompt:  return "settings.tab.prompt"
            case .tts:     return "settings.tab.tts"
            }
        }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .hotkey:  return "command"
            case .secret:  return "key"
            case .prompt:  return "text.bubble"
            case .tts:     return "speaker.wave.2"
            }
        }
    }

    @State private var tab: Tab = .general

    @State private var translateSelection: KeyBinding
    @State private var captureOCR: KeyBinding
    @State private var selectionToNote: KeyBinding
    @State private var recordingTranslate = false
    @State private var recordingCapture = false
    @State private var recordingToNote = false

    @State private var secretDrafts: [String: String] = [:]
    @State private var secretStatus: [AppController.SecretField] = []
    @State private var systemPrompt: String
    @State private var targetLanguage: TargetLanguage

    init(config: HotkeyConfig, promptConfig: PromptConfig) {
        _translateSelection = State(initialValue: config.translateSelection)
        _captureOCR = State(initialValue: config.captureOCR)
        _selectionToNote = State(initialValue: config.selectionToNote)
        _systemPrompt = State(initialValue: promptConfig.systemPrompt)
        _targetLanguage = State(initialValue: .chinese)
    }

    /// 三组绑定两两不可相同（任一对撞键即冲突，禁用保存）。
    private var hasConflict: Bool {
        func same(_ a: KeyBinding, _ b: KeyBinding) -> Bool {
            a.keyCode == b.keyCode && a.modifierFlags == b.modifierFlags
        }
        return same(translateSelection, captureOCR)
            || same(translateSelection, selectionToNote)
            || same(captureOCR, selectionToNote)
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch tab {
                    case .general: generalPage
                    case .hotkey:  hotkeyPage
                    case .secret:  secretPage
                    case .prompt:  promptPage
                    case .tts:     ttsPage
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 520, height: 600)
        .onAppear {
            secretStatus = controller.secretFields()
            targetLanguage = controller.languageConfig.target
        }
    }

    // MARK: - 顶部 Tab 条

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    tab = t
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.icon).font(.title3)
                        Text(LocalizedStringKey(t.titleKey))
                            .font(.caption)
                    }
                    .frame(width: 76, height: 50)
                    .background(tab == t
                        ? Color.accentColor.opacity(0.15) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(tab == t ? Color.accentColor : .secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 通用页（语言）

    private var generalPage: some View {
        settingsGroup("settings.general.lang_section") {
            HStack {
                Text("settings.general.target_lang")
                Spacer()
                Picker("", selection: $targetLanguage) {
                    ForEach(TargetLanguage.allCases, id: \.self) { lang in
                        Text(verbatim: "\(lang.flag) ")
                            + Text(LocalizedStringKey(lang.displayNameKey))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Divider()
            HStack {
                Text("settings.general.source_lang")
                Spacer()
                Text("lang.auto_detect").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 快捷键页

    private var hotkeyPage: some View {
        settingsGroup("settings.tab.hotkey") {
            keyRow("settings.hotkey.translate_selection",
                   "settings.hotkey.translate_selection.hint",
                   binding: $translateSelection,
                   recording: $recordingTranslate)
            Divider()
            keyRow("settings.hotkey.capture_ocr",
                   "settings.hotkey.capture_ocr.hint",
                   binding: $captureOCR,
                   recording: $recordingCapture)
            Divider()
            keyRow("settings.hotkey.selection_to_note",
                   "settings.hotkey.selection_to_note.hint",
                   binding: $selectionToNote,
                   recording: $recordingToNote)
            if hasConflict {
                Divider()
                Label("settings.hotkey.conflict",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Divider()
            Button("settings.hotkey.reset") {
                translateSelection = .defaultTranslateSelection
                captureOCR = .defaultCaptureOCR
                selectionToNote = .defaultSelectionToNote
            }
            .controlSize(.small)
        }
    }

    // MARK: - 密钥页

    private var secretPage: some View {
        settingsGroup("settings.secret.title", hint: "settings.secret.hint") {
            ForEach(Array(secretStatus.enumerated()), id: \.element.id) { idx, field in
                if idx > 0 { Divider() }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(LocalizedStringKey(field.titleKey))
                            .font(.subheadline)
                        if field.isSet {
                            Text("settings.secret.configured")
                                .font(.caption2).foregroundStyle(.green)
                        } else {
                            Text("settings.secret.not_configured")
                                .font(.caption2).foregroundStyle(.orange)
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
            Divider()
            Text("settings.secret.save_note")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - 提示词页

    private var promptPage: some View {
        settingsGroup("settings.prompt.title", hint: "settings.prompt.hint") {
            TextEditor(text: $systemPrompt)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 200)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3)))
            Divider()
            Button("settings.prompt.reset") {
                systemPrompt = PromptConfig.defaultSystemPrompt
            }
            .controlSize(.small)
        }
    }

    // MARK: - TTS 页（语音合成设置，实时生效）

    /// 引擎/发音人/口语化/语速/音量/音调。绑定 controller.ttsViewModel，
    /// didSet 即时重建 provider + debounce 存盘，故不走底部统一保存。
    private var ttsPage: some View {
        let tts = controller.ttsViewModel
        return settingsGroup("settings.tab.tts", hint: "settings.tts.hint") {
            HStack {
                Text("tts.engine")
                Spacer()
                Picker("", selection: Binding(
                    get: { tts.engine },
                    set: { tts.engine = $0 })) {
                    Text("tts.engine.super").tag(TTSEngine.superHuman)
                    Text("tts.engine.standard").tag(TTSEngine.standard)
                }
                .labelsHidden().fixedSize()
            }
            Divider()
            HStack {
                Text("tts.voice")
                Spacer()
                Picker("", selection: Binding(
                    get: { tts.vcn },
                    set: { tts.vcn = $0 })) {
                    ForEach(TTSPlaybackViewModel.vcnOptions(for: tts.engine),
                            id: \.value) { opt in
                        Text(opt.label).tag(opt.value)
                    }
                }
                .labelsHidden().fixedSize()
            }
            if tts.engine == .superHuman {
                Divider()
                HStack {
                    Text("tts.oral")
                    Spacer()
                    Picker("", selection: Binding(
                        get: { tts.oralLevel },
                        set: { tts.oralLevel = $0 })) {
                        Text("tts.oral.high").tag(TTSOralLevel.high)
                        Text("tts.oral.mid").tag(TTSOralLevel.mid)
                        Text("tts.oral.low").tag(TTSOralLevel.low)
                    }
                    .labelsHidden().fixedSize()
                }
            }
            Divider()
            ttsSlider("tts.speed",
                      get: { tts.speed }, set: { tts.speed = $0 })
            ttsSlider("tts.volume",
                      get: { tts.volume }, set: { tts.volume = $0 })
            ttsSlider("tts.pitch",
                      get: { tts.pitch }, set: { tts.pitch = $0 })
        }
    }

    @ViewBuilder
    private func ttsSlider(_ titleKey: LocalizedStringKey,
                           get: @escaping () -> Double,
                           set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(titleKey)
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Slider(value: Binding(get: get, set: set),
                   in: 0...100, step: 1)
            Text("\(Int(get()))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    // MARK: - 底部统一保存

    private var footer: some View {
        HStack {
            Spacer()
            Button("settings.hotkey.cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("settings.hotkey.save") {
                controller.updateHotkeyConfig(HotkeyConfig(
                    translateSelection: translateSelection,
                    captureOCR: captureOCR,
                    selectionToNote: selectionToNote))
                saveSecrets()
                controller.updatePromptConfig(
                    PromptConfig(systemPrompt: systemPrompt))
                controller.updateLanguageConfig(
                    LanguageConfig(target: targetLanguage))
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(hasConflict)
        }
        .padding(16)
    }

    private func saveSecrets() {
        for (key, value) in secretDrafts where
            !value.trimmingCharacters(in: .whitespaces).isEmpty {
            controller.saveSecret(value, forKey: key)
        }
        secretDrafts.removeAll()
        secretStatus = controller.secretFields()
    }

    // MARK: - 复用零件

    /// 分组卡：标题 + 可选说明 + 圆角容器内的行（对齐 Easydict 分区）。
    @ViewBuilder
    private func settingsGroup<Content: View>(
        _ titleKey: LocalizedStringKey,
        hint: LocalizedStringKey? = nil,
        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titleKey)
                .font(.headline)
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private func keyRow(_ titleKey: LocalizedStringKey,
                        _ hintKey: LocalizedStringKey,
                        binding: Binding<KeyBinding>,
                        recording: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleKey).font(.subheadline.weight(.medium))
            Text(hintKey).font(.caption).foregroundStyle(.secondary)
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(recording.wrappedValue
                                ? Color.accentColor
                                : Color.secondary.opacity(0.4),
                                lineWidth: recording.wrappedValue ? 2 : 1)
                        .frame(height: 32)
                    Text(recording.wrappedValue
                         ? String(localized: "settings.hotkey.press_keys")
                         : binding.wrappedValue.displayString)
                        .font(.body.monospaced())
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
