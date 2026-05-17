import AppKit
import SwiftUI

/// P2 整合组合根 + App 生命周期协调（`@MainActor`，UI 边界）。
///
/// 职责：
///  - 组装 `P2IntegrationCoordinator`（路由/截屏/OCR 真实适配）；
///  - 在 App 启动接入 `GlobalHotkeyMonitor`（⌘⇧D），触发截屏取词链；
///  - 把采集链结果灌进 `ContentQueryViewModel`（复用 P1 已验证查询管线）；
///  - 把 `.permission` 失败暴露给 UI，引导用户去系统设置。
///
/// 不在此重复实现几何/分类逻辑——只做组装与生命周期。真机手动验收。
@MainActor
final class AppController: ObservableObject {

    let queryViewModel: ContentQueryViewModel
    let ttsViewModel: TTSPlaybackViewModel
    let noteDocsViewModel: NoteDocumentsViewModel
    /// 原料包导出读全量翻译历史用(只读 results.jsonl)。
    let exportResultStore: JSONLResultStore

    /// 最近一次采集链失败分类（nil 表示无未处理的权限/采集错误）。
    /// UI 据此决定是否显示权限引导横幅。
    @Published private(set) var captureFailure: AgentError.Category?

    private let coordinator: P2IntegrationCoordinator
    private let hotkey: HotkeyMonitoring
    private let regionSelector: RegionSelectionController
    private let selectionGrabber: SelectionTextGrabber
    private let hotkeyStore: HotkeySettingsStore
    private let promptStore: PromptSettingsStore
    private let languageStore: LanguageSettingsStore
    private let secrets: SecretStore

    /// 当前系统提示词配置（设置界面读这个回显，保存后重建 LLM）。
    @Published private(set) var promptConfig: PromptConfig
    /// 当前语言配置（设置/语言方向条读这个回显）。
    @Published private(set) var languageConfig: LanguageConfig
    private var captureTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?

    /// 密钥配置项：account(Keychain key) + 展示名 + 是否已配置。
    /// 设置界面据此渲染 4 个输入框与"已配置/未配置"状态。
    struct SecretField: Identifiable {
        let id: String          // Keychain account，如 "llm.apiKey"
        let titleKey: String    // 本地化键
        var isSet: Bool
    }

    /// 当前生效的快捷键配置（设置界面读这个回显，保存后热重载）。
    @Published private(set) var hotkeyConfig: HotkeyConfig

    init() {
        let accessibility = SystemAccessibilityAuthorizer()
        let screenAuth = SystemScreenCaptureAuthorizer()

        self.queryViewModel = AppComposition.makeViewModel()
        self.ttsViewModel = AppComposition.makeTTSViewModel()
        self.noteDocsViewModel = AppComposition.makeNoteDocumentsViewModel()
        self.exportResultStore = AppComposition.makeResultStoreForExport()
        self.coordinator = P2IntegrationCoordinator(
            screenAuth: screenAuth,
            capture: ScreenCaptureCoordinator(
                authorizer: screenAuth,
                capturer: SCScreenCapturer()),
            ocr: OCRCoordinator(recognizer: VisionTextRecognizer()))

        let store = HotkeySettingsStore(
            fileURL: AppComposition.hotkeySettingsFileURL())
        let config = store.load()
        self.hotkeyStore = store
        let pStore = PromptSettingsStore(
            fileURL: AppComposition.promptSettingsFileURL())
        self.promptStore = pStore
        self.promptConfig = pStore.load()
        let lStore = LanguageSettingsStore(
            fileURL: AppComposition.languageSettingsFileURL())
        let lConfig = lStore.load()
        self.languageStore = lStore
        self.languageConfig = lConfig
        self.secrets = KeychainSecretStore()
        self.hotkeyConfig = config
        self.hotkey = GlobalHotkeyMonitor(
            authorizer: accessibility, config: config)
        self.regionSelector = RegionSelectionController()
        self.selectionGrabber = SelectionTextGrabber(
            pasteboard: SystemPasteboard(),
            keystroke: SystemCopyKeystrokeSender())
    }

    /// App 启动调用：尝试接入全局热键。未授权（辅助功能）时不崩溃，
    /// 记 `.permission` 让 UI 引导——用户仍可用界面按钮触发截屏取词。
    ///
    /// 自愈：监听 `didBecomeActiveNotification`（App 每次被切到前台都
    /// 发，比 SwiftUI scenePhase 可靠），用户在系统设置授权辅助功能后
    /// 切回本 App 即重试装热键，无需重启。
    func start() {
        // 把持久化的目标语言注入 ViewModel，并接变更回调落盘
        // （语言方向条切换 → didSet → 这里 → store.save）。
        queryViewModel.targetLanguage = languageConfig.target
        queryViewModel.onTargetLanguageChange = { [weak self] lang in
            guard let self else { return }
            self.languageConfig = LanguageConfig(target: lang)
            try? self.languageStore.save(self.languageConfig)
        }
        hotkey.onCaptureOCR = { [weak self] in
            Task { @MainActor in self?.triggerCapture() }
        }
        hotkey.onTranslateSelection = { [weak self] in
            Task { @MainActor in self?.triggerSelectionTranslate() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.retryHotkeyIfNeeded() }
        }
        retryHotkeyIfNeeded()
    }

    /// 全局热键是否已成功装上（辅助功能未授权时为 false）。
    @Published private(set) var hotkeyActive = false

    /// 幂等地尝试装热键。首次因辅助功能未授权失败后，用户授权并切回
    /// 窗口会再次调用（`.onAppear`/`scenePhase`），授权一旦生效即自愈，
    /// 无需重启 App。已装上则直接返回，不重复注册。
    func retryHotkeyIfNeeded() {
        guard !hotkeyActive else { return }
        do {
            try hotkey.start()
            hotkeyActive = true
            captureFailure = nil
        } catch let error as AgentError {
            captureFailure = error.category
        } catch {
            captureFailure = .unknown
        }
    }

    /// 触发一次截屏取词→查询。串行：进行中再次触发被忽略，避免叠 overlay。
    func triggerCapture() {
        guard captureTask == nil else { return }
        captureFailure = nil
        captureTask = Task { @MainActor in
            defer { captureTask = nil }
            let outcome = await coordinator.captureText(
                selectRegion: { [regionSelector] in
                    await regionSelector.selectRegion()
                })
            switch outcome {
            case .success(let captured):
                // 截屏成功、要展示结果了，此时才把主窗口调到前台
                // （框选阶段刻意不激活，让用户从任意 App 就地截屏）。
                NSApp.activate(ignoringOtherApps: true)
                // 对齐 Easydict：截屏 OCR 文本默认走翻译。
                await queryViewModel.runQuery(
                    with: captured.text, sourceKind: .screenshot,
                    action: .translate)
            case .failure(let error):
                // 取消回 idle 不报错、不打扰（用户主动放弃，不抢窗口）；
                // 其它失败（权限/采集错）需要用户看到引导横幅，激活窗口。
                if error.category != .cancelled {
                    NSApp.activate(ignoringOtherApps: true)
                    captureFailure = error.category
                }
                queryViewModel.reportCaptureFailure(error.category)
            }
        }
    }

    /// 触发一次划词翻译：模拟 ⌘C 取选中文字 → 翻译。串行：进行中
    /// 再次触发被忽略。抓不到选中文字（无选中）静默不做事——不弹窗、
    /// 不抢焦点（对齐 Easydict 默认，由 James 确认）。
    func triggerSelectionTranslate() {
        guard selectionTask == nil else { return }
        selectionTask = Task { @MainActor in
            defer { selectionTask = nil }
            switch await selectionGrabber.grab() {
            case .success(let text):
                // 拿到选中文字、要展示结果了，此时才把窗口调前台
                // （取词阶段刻意不激活，让用户从任意 App 就地划词）。
                NSApp.activate(ignoringOtherApps: true)
                await queryViewModel.runQuery(
                    with: text, sourceKind: .selectedText,
                    action: .translate)
            case .failure:
                // 无选中/空白：静默，不打扰用户。
                break
            }
        }
    }

    /// 保存新的快捷键配置：写盘 + 热重载监听（无需重启）。
    /// 写盘失败不阻断热重载（偏好持久化失败只损失"下次保留"）。
    func updateHotkeyConfig(_ config: HotkeyConfig) {
        hotkeyConfig = config
        hotkey.update(config)
        try? hotkeyStore.save(config)
    }

    // MARK: - 密钥配置（设置界面用）

    /// LLM + 讯飞 TTS 三件套的 Keychain account 名（与 AppComposition /
    /// TTSConfigStore 的引用常量保持一致，单一事实源在那边定义）。
    static let secretRefs: [(id: String, titleKey: String)] = [
        ("llm.apiKey",    "settings.secret.llm_api_key"),
        ("tts.appId",     "settings.secret.tts_app_id"),
        ("tts.apiKey",    "settings.secret.tts_api_key"),
        ("tts.apiSecret", "settings.secret.tts_api_secret")
    ]

    /// 当前各密钥是否已配置（不返回明文，UI 只显示"已配置/未配置"）。
    func secretFields() -> [SecretField] {
        Self.secretRefs.map { ref in
            let exists = (try? secrets.secret(forKey: ref.id)) ?? nil
            return SecretField(id: ref.id, titleKey: ref.titleKey,
                               isSet: !(exists ?? "").isEmpty)
        }
    }

    /// 写入一个密钥（去首尾空白；空串视为"清除该项"）。
    /// 通过 app 内写入，ACL 自动绑定当前签名，根治反复弹密码。
    /// 返回是否成功，UI 据此提示。
    @discardableResult
    func saveSecret(_ value: String, forKey key: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try secrets.deleteSecret(forKey: key)
            } else {
                try secrets.setSecret(trimmed, forKey: key)
            }
            // 关键：密钥变更后按新 key 重建 LLM provider，否则启动时
            // 注入的 FailingLLMProvider 不会被替换，填了 key 仍报
            // "配置缺失"。TTS 经各自 ViewModel 的 settingsChanged
            // 重建,LLM 走这里。
            if key == AppComposition.apiKeyRef {
                queryViewModel.replaceProvider(AppComposition.makeLLMProvider())
            }
            return true
        } catch {
            return false
        }
    }

    /// 保存语言配置：写盘 + 推到 ViewModel（语言方向条同步生效）。
    func updateLanguageConfig(_ config: LanguageConfig) {
        languageConfig = config
        try? languageStore.save(config)
        queryViewModel.targetLanguage = config.target
    }

    /// 保存系统提示词：写盘 + 重建 LLM provider（立即生效，无需
    /// 重启）。空串由 store sanitize 回默认。
    func updatePromptConfig(_ config: PromptConfig) {
        promptConfig = config
        try? promptStore.save(config)
        // provider 持有 systemPrompt 的快照，必须重建才生效。
        queryViewModel.replaceProvider(AppComposition.makeLLMProvider())
    }

    /// 打开"系统设置 > 隐私与安全性 > 屏幕录制"（权限引导）。
    /// 辅助功能/录屏面板 deep link 不稳定，落到隐私与安全性根面板即可，
    /// 用户可在侧栏选对应项；这是诚实的可达兜底而非脆弱深链。
    func openPrivacySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy")!
        NSWorkspace.shared.open(url)
    }

    func dismissCaptureFailure() {
        captureFailure = nil
    }
}
