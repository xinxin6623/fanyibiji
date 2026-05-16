import SwiftUI

@main
struct PersonalAgentApp: App {
    @StateObject private var controller = AppController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainWindowView(viewModel: controller.queryViewModel)
                .environmentObject(controller)
                .onAppear { controller.start() }
        }
        // App 重新激活时重试装热键：用户在系统设置授权辅助功能后，
        // 切回本 App 即自愈，无需重启（首次未授权不致永久失效）。
        // 单参 onChange 兼容 macOS 13（双参版本 14+）。
        .onChange(of: scenePhase) { phase in
            if phase == .active { controller.retryHotkeyIfNeeded() }
        }
    }
}
