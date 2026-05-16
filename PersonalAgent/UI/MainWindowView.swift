import SwiftUI

struct MainWindowView: View {
    @StateObject private var viewModel = AppComposition.makeViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("app.title")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("query.prompt")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.inputText)
                .font(.body)
                .frame(minHeight: 100)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3)))

            HStack {
                Button {
                    Task { await viewModel.runQuery() }
                } label: {
                    Text("query.run")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isLoading)

                if isLoading {
                    ProgressView().controlSize(.small)
                }
            }

            Divider()

            resultArea
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(28)
        .frame(minWidth: 560, minHeight: 420)
    }

    private var isLoading: Bool {
        if case .loading = viewModel.state { return true }
        return false
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
            Label {
                Text(Self.messageKey(for: category))
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
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
