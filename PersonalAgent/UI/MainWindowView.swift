import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var controller: AppController
    @ObservedObject private var viewModel: ContentQueryViewModel
    @State private var showingHistory = false

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

                Button {
                    showingHistory.toggle()
                    if showingHistory { viewModel.loadHistory() }
                } label: {
                    Text(showingHistory ? "history.hide" : "history.show")
                }
            }

            Text("capture.hint")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Group {
                if showingHistory {
                    historyArea
                } else {
                    resultArea
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            TTSPanelView(viewModel: controller.ttsViewModel)

            Spacer()
        }
        .padding(28)
        .frame(minWidth: 560, minHeight: 520)
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
                     : category.localizationKey)
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
                    Text(category.localizationKey)
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

    @ViewBuilder
    private var historyArea: some View {
        if let cat = viewModel.historyError {
            Label {
                Text(cat.localizationKey)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        } else if viewModel.history.isEmpty {
            Text("history.empty").foregroundStyle(.secondary)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.history, id: \.id) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.provider)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                if item.error != nil {
                                    Text("history.failed_tag")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                Spacer()
                                Text(item.createdAt, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(resultText(item).isEmpty
                                 ? "—" : resultText(item))
                                .font(.body)
                                .textSelection(.enabled)
                                .lineLimit(4)
                        }
                        Divider()
                    }
                }
            }
        }
    }

    private func resultText(_ model: ResultModel) -> String {
        if case let .text(value) = model.content { return value }
        if case let .translation(t, _, _) = model.content { return t }
        return ""
    }

    /// category → 本地化键。UI 不拼接 provider 私有错误。
}
