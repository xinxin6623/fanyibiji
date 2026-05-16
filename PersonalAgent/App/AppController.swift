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

    /// 最近一次采集链失败分类（nil 表示无未处理的权限/采集错误）。
    /// UI 据此决定是否显示权限引导横幅。
    @Published private(set) var captureFailure: AgentError.Category?

    private let coordinator: P2IntegrationCoordinator
    private let hotkey: HotkeyMonitoring
    private let regionSelector: RegionSelectionController
    private var captureTask: Task<Void, Never>?

    init() {
        let accessibility = SystemAccessibilityAuthorizer()
        let screenAuth = SystemScreenCaptureAuthorizer()

        self.queryViewModel = AppComposition.makeViewModel()
        self.coordinator = P2IntegrationCoordinator(
            screenAuth: screenAuth,
            capture: ScreenCaptureCoordinator(
                authorizer: screenAuth,
                capturer: SCScreenCapturer()),
            ocr: OCRCoordinator(recognizer: VisionTextRecognizer()))
        self.hotkey = GlobalHotkeyMonitor(authorizer: accessibility)
        self.regionSelector = RegionSelectionController()
    }

    /// App 启动调用：尝试接入全局热键。未授权（辅助功能）时不崩溃，
    /// 记 `.permission` 让 UI 引导——用户仍可用界面按钮触发截屏取词。
    ///
    /// 自愈：监听 `didBecomeActiveNotification`（App 每次被切到前台都
    /// 发，比 SwiftUI scenePhase 可靠），用户在系统设置授权辅助功能后
    /// 切回本 App 即重试装热键，无需重启。
    func start() {
        hotkey.onTrigger = { [weak self] in
            Task { @MainActor in self?.triggerCapture() }
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
