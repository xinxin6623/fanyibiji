import AppKit
import SwiftUI

/// P2 整合组合根 + App 生命周期协调（`@MainActor`，UI 边界）。
///
/// 职责：
///  - 组装 `P2IntegrationCoordinator`（路由/截屏/OCR 真实适配）；
///  - 在 App 启动接入 `GlobalHotkeyMonitor`（⌘⇧A），触发截屏取词链；
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
            router: InputRouter(authorizer: accessibility),
            capture: ScreenCaptureCoordinator(
                authorizer: screenAuth,
                capturer: SCScreenCapturer()),
            ocr: OCRCoordinator(recognizer: VisionTextRecognizer()))
        self.hotkey = GlobalHotkeyMonitor(authorizer: accessibility)
        self.regionSelector = RegionSelectionController()
    }

    /// App 启动调用：尝试接入全局热键。未授权（辅助功能）时不崩溃，
    /// 记 `.permission` 让 UI 引导——用户仍可用界面按钮触发截屏取词。
    func start() {
        hotkey.onTrigger = { [weak self] in
            Task { @MainActor in self?.triggerCapture() }
        }
        do {
            try hotkey.start()
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
                // 对齐 Easydict：截屏 OCR 文本默认走翻译。
                await queryViewModel.runQuery(
                    with: captured.text, sourceKind: .screenshot,
                    action: .translate)
            case .failure(let error):
                // 取消回 idle 不报错；权限等分类显示引导横幅 + UI 失败态。
                if error.category != .cancelled {
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
