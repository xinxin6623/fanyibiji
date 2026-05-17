import SwiftUI

/// TTS 播放状态条（仅状态/进度/暂停/失败）。
///
/// 文本输入框与合成设置已移除：
///  - 合成由主窗口"朗读输入/朗读结果"图标按钮触发（直接传文本）。
///  - 引擎/发音人/语速等设置移入设置 sheet 的 TTS Tab。
/// 本视图只在有合成任务时显示进度与播放控制，空闲不占位。
struct TTSPanelView: View {
    @ObservedObject private var viewModel: TTSPlaybackViewModel

    init(viewModel: TTSPlaybackViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        if shouldShow {
            VStack(alignment: .leading, spacing: 8) {
                if isSynthesizing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("tts.synthesizing")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if viewModel.canCancel {
                            Button("tts.cancel") {
                                viewModel.cancelSynthesis()
                            }
                            .controlSize(.small)
                        }
                    }
                }

                if case .ready = viewModel.state {
                    playbackControls
                }

                if case let .failure(category) = viewModel.state {
                    Label {
                        Text(Self.messageKey(for: category))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// 空闲态不渲染（不占卡片位）；合成中/可播放/失败才显示。
    private var shouldShow: Bool {
        switch viewModel.state {
        case .idle: return false
        case .synthesizing, .ready, .failure: return true
        }
    }

    private var isSynthesizing: Bool {
        if case .synthesizing = viewModel.state { return true }
        return false
    }

    @ViewBuilder
    private var playbackControls: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.togglePlayPause()
            } label: {
                Image(systemName: viewModel.isPlaying
                      ? "pause.fill" : "play.fill")
                Text(viewModel.isPlaying ? "tts.pause" : "tts.play")
            }

            Slider(
                value: Binding(
                    get: { viewModel.progress },
                    set: { viewModel.seek(toFraction: $0) }),
                in: 0...1)
        }
    }

    /// category → 本地化键（与 MainWindowView 保持一致）。
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
