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
/// 四个 Tab：通用(语言) / 快捷键 / 模型(LLM key+baseUrl+model+提示词) /
/// 转语音(TTS 三件套+语音设置)。底部统一保存。
struct HotkeySettingsView: View {
    @EnvironmentObject private var controller: AppController
    @Environment(\.dismiss) private var dismiss

    private enum Tab: String, CaseIterable {
        case general, hotkey, model, voice
        var titleKey: String {
            switch self {
            case .general: return "settings.tab.general"
            case .hotkey:  return "settings.tab.hotkey"
            case .model:   return "settings.tab.model"
            case .voice:   return "settings.tab.voice"
            }
        }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .hotkey:  return "command"
            case .model:   return "brain"
            case .voice:   return "speaker.wave.2"
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
    @State private var llmBaseUrl: String
    @State private var llmModel: String

    init(config: HotkeyConfig,
         promptConfig: PromptConfig,
         llmConfig: ProviderConfig) {
        _translateSelection = State(initialValue: config.translateSelection)
        _captureOCR = State(initialValue: config.captureOCR)
        _selectionToNote = State(initialValue: config.selectionToNote)
        _systemPrompt = State(initialValue: promptConfig.systemPrompt)
        _targetLanguage = State(initialValue: .chinese)
        _llmBaseUrl = State(initialValue: llmConfig.baseUrl)
        _llmModel = State(initialValue: llmConfig.model)
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
                    case .model:   modelPage
                    case .voice:   voicePage
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

    // MARK: - 模型页（LLM baseUrl / model / api key / 系统提示词）

    /// 模型设置统一页：上半部分是 baseUrl + model + LLM API Key
    /// （非密钥字段走 controller.llmConfig 持久化，密钥走 SecretStore），
    /// 下半部分是系统提示词。底部统一保存按钮里一次写盘 + 重建 provider。
    private var modelPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("settings.model.title",
                          hint: "settings.model.hint") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.llm.base_url").font(.subheadline)
                    TextField(
                        "settings.llm.base_url_placeholder",
                        text: $llmBaseUrl)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.llm.model").font(.subheadline)
                    TextField(
                        "settings.llm.model_placeholder",
                        text: $llmModel)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
                Divider()
                secretRow(forKey: "llm.apiKey",
                          titleKey: "settings.secret.llm_api_key")
            }
            settingsGroup("settings.prompt.title",
                          hint: "settings.prompt.hint") {
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
    }

    // MARK: - 转语音页（TTS 三件套密钥 + 语音合成设置）

    /// 上半部分是讯飞 TTS 三件套密钥（同走 SecretStore，底部统一保存）；
    /// 下半部分引擎/发音人/口语化/语速/音量/音调（绑定 ttsViewModel，
    /// didSet 即时重建 provider + debounce 存盘，独立于底部保存）。
    private var voicePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 两套引擎密钥**同时显示**：用户可两边都预先配好，再用下方「引擎」
            // picker 切换实际使用哪个，无需为了配置一方先牺牲另一方。
            settingsGroup("settings.voice.secret.title",
                          hint: "settings.voice.secret.hint") {
                secretRow(forKey: "tts.appId",
                          titleKey: "settings.secret.tts_app_id")
                Divider()
                secretRow(forKey: "tts.apiKey",
                          titleKey: "settings.secret.tts_api_key")
                Divider()
                secretRow(forKey: "tts.apiSecret",
                          titleKey: "settings.secret.tts_api_secret")
            }
            settingsGroup("settings.voice.doubao.secret.title",
                          hint: "settings.voice.doubao.secret.hint") {
                secretRow(forKey: "tts.doubao.appId",
                          titleKey: "settings.secret.doubao_app_id")
                Divider()
                secretRow(forKey: "tts.doubao.token",
                          titleKey: "settings.secret.doubao_token")
            }
            ttsControlsGroup
        }
    }

    /// 单条密钥行（标题 + 已配置/未配置标 + 输入框）。模型页/转语音页共用。
    @ViewBuilder
    private func secretRow(forKey key: String,
                           titleKey: String) -> some View {
        let field = secretStatus.first(where: { $0.id == key })
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(LocalizedStringKey(titleKey)).font(.subheadline)
                if field?.isSet == true {
                    Text("settings.secret.configured")
                        .font(.caption2).foregroundStyle(.green)
                } else {
                    Text("settings.secret.not_configured")
                        .font(.caption2).foregroundStyle(.orange)
                }
            }
            SecureField(
                (field?.isSet ?? false)
                    ? String(localized: "settings.secret.placeholder_set")
                    : String(localized: "settings.secret.placeholder_empty"),
                text: Binding(
                    get: { secretDrafts[key] ?? "" },
                    set: { secretDrafts[key] = $0 }))
                .textFieldStyle(.roundedBorder)
        }
    }

    /// 语音合成参数分组（引擎/发音人/口语化/三个滑杆）。从原 ttsPage 抽出。
    private var ttsControlsGroup: some View {
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
                    Text("tts.engine.doubao").tag(TTSEngine.doubao)
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
                // 先存 LLM baseUrl/model，再存提示词；后者也会重建
                // provider，等同于一次合并写盘。
                controller.updateLLMConfig(ProviderConfig(
                    baseUrl: llmBaseUrl
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    model: llmModel
                        .trimmingCharacters(in: .whitespacesAndNewlines)))
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
