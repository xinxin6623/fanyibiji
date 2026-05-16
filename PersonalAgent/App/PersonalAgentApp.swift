import SwiftUI

@main
struct PersonalAgentApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        WindowGroup {
            MainWindowView(viewModel: controller.queryViewModel)
                .environmentObject(controller)
                .onAppear { controller.start() }
        }
    }
}
