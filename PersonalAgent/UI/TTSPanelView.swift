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

    /// 讯飞 speed 0–100 → 展示倍率 0.5x–2.0x（线性，50→1.0x）。
    /// 讯飞接口无"真实倍率"语义，这里只是给人看的友好映射；写回
    /// viewModel.speed 仍是 0–100 整数（provider 用的就是它）。
    private static let minRate = 0.5
    private static let maxRate = 2.0

    /// 每点一次 << / >> 的步进倍率。
    private static let rateStep = 0.1

    private func rate(from speed: Double) -> Double {
        Self.minRate + (speed / 100) * (Self.maxRate - Self.minRate)
    }

    private func speed(from rate: Double) -> Double {
        ((rate - Self.minRate) / (Self.maxRate - Self.minRate)) * 100
    }

    /// 按步进增减倍率（夹在 0.5x–2x），写回 viewModel.speed。
    private func bumpRate(by delta: Double) {
        let cur = rate(from: viewModel.speed)
        let next = min(max(cur + delta, Self.minRate), Self.maxRate)
        viewModel.speed = speed(from: next)
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

                // 速度：滑块删掉（James 决策），改 << / >> 步进按钮，
                // 中间显示当前倍率。每点一次 ±0.1x，夹在 0.5x–2x。
                HStack(spacing: 8) {
                    Button("<<") { bumpRate(by: -Self.rateStep) }
                        .buttonStyle(.plain)
                        .foregroundStyle(ClaudeTheme.accent)
                        .disabled(rate(from: viewModel.speed)
                                  <= Self.minRate + 0.001)
                    Text(String(format: "%.1fx", rate(from: viewModel.speed)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ClaudeTheme.secondaryText)
                        .frame(width: 38)
                    Button(">>") { bumpRate(by: Self.rateStep) }
                        .buttonStyle(.plain)
                        .foregroundStyle(ClaudeTheme.accent)
                        .disabled(rate(from: viewModel.speed)
                                  >= Self.maxRate - 0.001)
                }
                .font(.subheadline.weight(.semibold))
                .fixedSize()
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
