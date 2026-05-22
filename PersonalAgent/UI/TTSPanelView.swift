import SwiftUI

/// TTS 播放条（常驻左栏顶部）。
///
/// 布局参考 James 给的设计图：单行「▶播放 ── 进度条」，下方加一行
/// 「速度 ── 0.5x–2x 滑块」。合成由主窗口"朗读输入/朗读结果"图标
/// 按钮触发（直接传文本）；引擎/发音人等其余设置仍在设置 sheet。
///
/// 与旧版差异：旧版空闲不渲染（不占位），现按需求**常驻顶部**——
/// 空闲态显示禁用的播放控件占位，合成中显示进度，失败显示告警。
struct TTSPanelView: View {
    @ObservedObject private var viewModel: TTSPlaybackViewModel

    init(viewModel: TTSPlaybackViewModel) {
        self.viewModel = viewModel
    }

    /// 播放倍率范围（落到 `AVAudioPlayer.rate`，对正在播放的音频实时生效）。
    /// 旧版误把 `<< / >>` 写在合成参数 `speed`（0–100）上，只下次合成生效；
    /// 现切到 `playbackRate`，纯播放器侧变速，不变调。
    private static let minRate = 0.5
    private static let maxRate = 2.0
    private static let rateStep = 0.1

    /// 按步进增减播放倍率，夹在 0.5x–2x。
    private func bumpRate(by delta: Double) {
        let next = min(max(viewModel.playbackRate + delta, Self.minRate),
                       Self.maxRate)
        viewModel.playbackRate = next
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 单行：播放（纯文字图标，无底框）+ 进度条（占主空间）
            // ｜ 速度滑块 + 「<< 1.3x >>」倍率（无"语速"二字）。
            HStack(spacing: 12) {
                Button {
                    viewModel.togglePlayPause()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isPlaying
                              ? "pause.fill" : "play.fill")
                        Text(viewModel.isPlaying ? "tts.pause" : "tts.play")
                    }
                    .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(canPlay ? ClaudeTheme.primaryText
                                         : ClaudeTheme.secondaryText)
                .disabled(!canPlay)

                // 进度条——主空间。
                Slider(
                    value: Binding(
                        get: { viewModel.progress },
                        set: { viewModel.seek(toFraction: $0) }),
                    in: 0...1)
                .tint(ClaudeTheme.accent)
                .disabled(!canPlay)

                if isSynthesizing {
                    ProgressView().controlSize(.small)
                    if viewModel.canCancel {
                        Button("tts.cancel") {
                            viewModel.cancelSynthesis()
                        }
                        .controlSize(.small)
                    }
                }

                ClaudeTheme.separator.frame(width: 1, height: 18)

                // 引擎切换：普通 / 超拟人。Menu 走 borderless 紧贴在
                // 速度区左侧，文字随当前引擎变化。改了立即重建 provider，
                // 下次合成生效（已就绪音频不重合成）。
                Menu {
                    ForEach(TTSEngine.allCases, id: \.self) { eng in
                        Button {
                            viewModel.engine = eng
                        } label: {
                            if viewModel.engine == eng {
                                Label(Self.engineLabel(eng), systemImage: "checkmark")
                            } else {
                                Text(Self.engineLabel(eng))
                            }
                        }
                    }
                } label: {
                    Text(Self.engineLabel(viewModel.engine))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ClaudeTheme.secondaryText)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                // 速度：<< / >> 步进按钮调 playbackRate（对正在播放的
                // 音频实时变速）。紧凑化：去掉外层 fixedSize 留白，缩小
                // 间距 8→4 与倍率文本宽度 38→30。
                HStack(spacing: 4) {
                    Button("<<") { bumpRate(by: -Self.rateStep) }
                        .buttonStyle(.plain)
                        .foregroundStyle(ClaudeTheme.accent)
                        .disabled(viewModel.playbackRate
                                  <= Self.minRate + 0.001)
                    Text(String(format: "%.1fx", viewModel.playbackRate))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ClaudeTheme.secondaryText)
                        .frame(width: 30)
                    Button(">>") { bumpRate(by: Self.rateStep) }
                        .buttonStyle(.plain)
                        .foregroundStyle(ClaudeTheme.accent)
                        .disabled(viewModel.playbackRate
                                  >= Self.maxRate - 0.001)
                }
                .font(.subheadline.weight(.semibold))
            }

            if case let .failure(category) = viewModel.state {
                Label {
                    Text(Self.messageKey(for: category))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 有音频可播放（ready 态）才让播放按钮/进度条可用。
    private var canPlay: Bool {
        if case .ready = viewModel.state { return true }
        return false
    }

    private var isSynthesizing: Bool {
        if case .synthesizing = viewModel.state { return true }
        return false
    }

    /// 引擎在播放条上的短标签（要紧凑，避免占太多顶栏宽度）。
    private static func engineLabel(_ engine: TTSEngine) -> String {
        switch engine {
        case .standard:   return "普通"
        case .superHuman: return "超拟人"
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
