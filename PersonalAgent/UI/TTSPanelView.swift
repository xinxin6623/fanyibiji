import SwiftUI

/// TTS 面板：输入框 → 一键「合成并播放」→ 可拖动进度条 + 播放/暂停。
///
/// 失败仅按 `AgentError.Category` 显示本地化文案（不拼 provider 私有
/// 错误，与主窗口 `messageKey(for:)` 同策略）。
struct TTSPanelView: View {
    @ObservedObject private var viewModel: TTSPlaybackViewModel

    init(viewModel: TTSPlaybackViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("tts.section")
                .font(.headline)
                .foregroundStyle(.secondary)

            TextEditor(text: $viewModel.inputText)
                .font(.body)
                .frame(minHeight: 72)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3)))

            settingsControls

            HStack(spacing: 12) {
                Button {
                    viewModel.synthesizeAndPlay()
                } label: {
                    Text("tts.run")
                }
                .disabled(isSynthesizing
                          || viewModel.inputText.trimmingCharacters(
                              in: .whitespacesAndNewlines).isEmpty)

                if isSynthesizing {
                    ProgressView().controlSize(.small)
                    Text("tts.synthesizing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if viewModel.canCancel {
                        Button("tts.cancel") { viewModel.cancelSynthesis() }
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
    }

    /// 引擎下拉 + 发音人下拉（随引擎联动两套）+ 超拟人口语化下拉
    /// + 语速/音量/音调三滑块。改动经 ViewModel 即时重建 provider 并
    /// debounce 存盘（下次开 App 保留）。
    @ViewBuilder
    private var settingsControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("tts.engine", selection: $viewModel.engine) {
                Text("tts.engine.super").tag(TTSEngine.superHuman)
                Text("tts.engine.standard").tag(TTSEngine.standard)
            }
            .pickerStyle(.menu)
            .fixedSize()

            Picker("tts.voice", selection: $viewModel.vcn) {
                ForEach(TTSPlaybackViewModel.vcnOptions(for: viewModel.engine),
                        id: \.value) { opt in
                    Text(opt.label).tag(opt.value)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            if viewModel.engine == .superHuman {
                Picker("tts.oral", selection: $viewModel.oralLevel) {
                    Text("tts.oral.high").tag(TTSOralLevel.high)
                    Text("tts.oral.mid").tag(TTSOralLevel.mid)
                    Text("tts.oral.low").tag(TTSOralLevel.low)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }

            sliderRow("tts.speed", value: $viewModel.speed)
            sliderRow("tts.volume", value: $viewModel.volume)
            sliderRow("tts.pitch", value: $viewModel.pitch)
        }
    }

    @ViewBuilder
    private func sliderRow(_ titleKey: LocalizedStringKey,
                           value: Binding<Double>) -> some View {
        HStack(spacing: 10) {
            Text(titleKey)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            Slider(value: value, in: 0...100, step: 1)
            Text("\(Int(value.wrappedValue))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
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
