import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var controller: AppController
    @ObservedObject private var viewModel: ContentQueryViewModel

    init(viewModel: ContentQueryViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("app.title")
                .font(.largeTitle)
                .fontWeight(.semibold)

            if let category = controller.captureFailure {
                permissionBanner(category)
            }

            Text("query.prompt")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.inputText)
                .font(.body)
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3)))

            HStack(spacing: 12) {
                Button {
                    viewModel.dispatch { await viewModel.runQuery() }
                } label: {
                    Text("query.run")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isLoading)

                Button {
                    controller.triggerCapture()
                } label: {
                    Text("capture.run")
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(isLoading)

                if isLoading {
                    ProgressView().controlSize(.small)
                    if viewModel.canCancel {
                        Button("query.cancel") { viewModel.cancelCurrent() }
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.dispatch { await viewModel.queryFromClipboard() }
                } label: {
                    Text("clipboard.query")
                }
                .disabled(isLoading)

                Button {
                    viewModel.dispatch {
                        await viewModel.translateFromClipboard()
                    }
                } label: {
                    Text("clipboard.translate")
                }
                .disabled(isLoading)
            }

            Text("capture.hint")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            resultArea
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(28)
        .frame(minWidth: 560, minHeight: 460)
    }

    private var isLoading: Bool {
        if case .loading = viewModel.state { return true }
        return false
    }

    @ViewBuilder
    private func permissionBanner(_ category: AgentError.Category) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(category == .permission
                     ? "permission.guide"
                     : Self.messageKey(for: category))
            } icon: {
                Image(systemName: "lock.shield")
                    .foregroundStyle(.orange)
            }
            if category == .permission {
                Button("permission.open_settings") {
                    controller.openPrivacySettings()
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var resultArea: some View {
        switch viewModel.state {
        case .idle:
            Text("query.idle").foregroundStyle(.secondary)
        case .loading:
            Text("query.loading").foregroundStyle(.secondary)
        case let .success(model):
            ScrollView {
                Text(resultText(model))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case let .failure(category):
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text(Self.messageKey(for: category))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                if viewModel.canRetry {
                    Button("query.retry") {
                        viewModel.dispatch { await viewModel.retryLast() }
                    }
                }
            }
        }
    }

    private func resultText(_ model: ResultModel) -> String {
        if case let .text(value) = model.content { return value }
        return ""
    }

    /// category → 本地化键。UI 不拼接 provider 私有错误。
    private static func messageKey(for category: AgentError.Category) -> LocalizedStringKey {
        switch category {
        case .invalidInput:     return "error.invalid_input"
        case .network:          return "error.network"
        case .timeout:          return "error.timeout"
        case .cancelled:        return "error.cancelled"
        case .permission:       return "error.permission"
        case .persistence:      return "error.persistence"
        case .providerRejected: return "error.provider_rejected"
        case .unknown:          return "error.unknown"
        }
    }
}
