import Foundation
import AVFoundation

/// TTS 合成 + 播放的编排层（无 SwiftUI 依赖，可 headless 单测合成路径）。
///
/// 输入框文本 → `TTSProvider.synthesize` → `AVAudioPlayer` 播放，
/// 暴露 `progress`（0–1，可拖动 seek）与播放/暂停。失败仅暴露
/// `AgentError.Category`，文案在 View 层本地化（与 `ContentQueryViewModel`
/// 一致）。播放器交互限主线程（`@MainActor`）。
@MainActor
final class TTSPlaybackViewModel: NSObject, ObservableObject {

    enum State: Equatable {
        case idle
        case synthesizing
        /// 已拿到音频、可播放（含播放中/暂停，细分看 `isPlaying`）。
        case ready
        case failure(AgentError.Category)
    }

    @Published private(set) var state: State = .idle
    @Published var inputText: String = ""
    @Published private(set) var isPlaying = false
    /// 播放进度 0–1。拖动后调用 `seek(to:)` 落到播放器。
    @Published var progress: Double = 0
    @Published private(set) var durationSeconds: Double = 0

    // MARK: - 可调设置（UI 绑定；改动即重建 provider 并存盘）

    /// 引擎：普通 / 超拟人。切换时 vcn 自动落到该引擎默认发音人
    /// （两套发音人不通用，沿用旧 vcn 会「服务方拒绝」）。
    @Published var engine: TTSEngine {
        didSet {
            guard engine != oldValue else { return }
            // 引擎变 → vcn 重置为该引擎默认；vcn 的 didSet 会触发
            // settingsChanged()（含 host 随新引擎），无需此处重复调用。
            vcn = engine.defaultVcn
        }
    }
    /// 发音人。两套预置见 `vcnOptions(for:)`；切引擎时被重置。
    @Published var vcn: String { didSet { settingsChanged() } }
    @Published var speed: Double { didSet { settingsChanged() } }
    @Published var volume: Double { didSet { settingsChanged() } }
    @Published var pitch: Double { didSet { settingsChanged() } }

    /// 播放倍率 0.5x–2.0x，独立于合成参数 `speed`：作用在 `AVAudioPlayer.rate`
    /// 上，对**已合成、正在播放**的音频实时变速（AVFoundation 自动做时间
    /// 拉伸，不变调）。设置不入盘、不重建 provider——纯本地播放偏好。
    @Published var playbackRate: Double = 1.0 {
        didSet { player?.rate = Float(playbackRate) }
    }
    /// 口语化程度，仅 `superHuman` 引擎生效（standard 忽略）。
    @Published var oralLevel: TTSOralLevel { didSet { settingsChanged() } }

    /// 按引擎给预置发音人列表（label 给人看，value=vcn 传讯飞）。
    /// 控制台开通的冷门发音人不在此列也可用——但 UI 走预置下拉，
    /// 避免手输拼错导致「服务方拒绝」（经 James 确认走下拉）。
    static func vcnOptions(for engine: TTSEngine) -> [(label: String, value: String)] {
        switch engine {
        case .standard:
            return [
                ("讯飞小燕·女声", "xiaoyan"),
                ("讯飞许久·男声", "aisjiuxu"),
                ("讯飞小萍·女声", "aisxping"),
                ("讯飞小婧·女声", "aisjinger"),
                ("讯飞许小宝·童声", "aisbabyxu")
            ]
        case .superHuman:
            return [
                ("聪小璇·女声", "x5_lingxiaoxuan_flow"),
                ("聪飞逸·男声", "x5_lingfeiyi_flow"),
                ("聪小玥·女声", "x5_lingxiaoyue_flow"),
                ("聪玉昭·女声", "x5_lingyuzhao_flow"),
                ("聪玉言·女声", "x5_lingyuyan_flow")
            ]
        case .doubao:
            // 大模型 TTS service 10007「字符版」正式开通后默认授权的
            // moon_bigtts 系（共 348 款，这里挑 10 款覆盖三类典型场景）。
            // 命名 `zh_<gender>_<name>_moon_bigtts`，与 mars/jupiter 系
            // 不通用——若哪天切到不同服务需要重写。默认 `少年梓辛`
            // （中英双语，最适合翻译朗读）。
            // 顺序按用途分组：通用 → 角色扮演 → 趣味方言。
            return [
                // —— 通用场景 ——
                ("少年梓辛·中英男声", "zh_male_shaonianzixin_moon_bigtts"),
                // —— 角色扮演 ——
                ("魅力女友", "zh_female_meilinvyou_moon_bigtts"),
                ("柔美女友", "zh_female_sajiaonvyou_moon_bigtts"),
                ("撒娇学妹", "zh_female_yuanqinvyou_moon_bigtts"),
                ("深夜播客·男声", "zh_male_shenyeboke_moon_bigtts"),
                // —— 趣味方言 ——
                ("湾区大叔·粤语", "zh_female_wanqudashu_moon_bigtts"),
                ("呆萌川妹·四川话", "zh_female_daimengchuanmei_moon_bigtts"),
                ("广州德哥·粤语", "zh_male_guozhoudege_moon_bigtts"),
                ("北京小爷·京腔", "zh_male_beijingxiaoye_moon_bigtts"),
                ("浩宇小哥·东北话", "zh_male_haoyuxiaoge_moon_bigtts")
            ]
        }
    }

    private let makeProvider: @Sendable (TTSConfig) -> TTSProvider
    private let settingsStore: TTSSettingsStore
    private let baseConfig: TTSConfig
    private var provider: TTSProvider
    private var player: AVAudioPlayer?
    private var ticker: Timer?
    private var synthesisTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    /// - Parameters:
    ///   - settings: 启动时从盘读出的配置（含 host/timeout 等非 UI 字段）。
    ///   - settingsStore: 改动后落盘的目标。
    ///   - makeProvider: 按当前 `TTSConfig` 造 provider 的工厂（注入便于
    ///     单测；生产用 `AppComposition`）。
    init(settings: TTSConfig,
         settingsStore: TTSSettingsStore,
         makeProvider: @escaping @Sendable (TTSConfig) -> TTSProvider) {
        self.baseConfig = settings
        self.settingsStore = settingsStore
        self.makeProvider = makeProvider
        self.engine = settings.engine
        self.vcn = settings.vcn
        self.speed = Double(settings.speed)
        self.volume = Double(settings.volume)
        self.pitch = Double(settings.pitch)
        self.oralLevel = settings.oralLevel
        self.provider = makeProvider(settings)
        super.init()
    }

    /// 把当前 UI 值合回完整 `TTSConfig`。host 随 engine（不沿用旧
    /// baseConfig.hostUrl，否则切引擎后还连旧 host）；timeout 保留。
    private var currentConfig: TTSConfig {
        TTSConfig(engine: engine,
                  hostUrl: engine.defaultHost,
                  vcn: vcn,
                  speed: Int(speed.rounded()),
                  volume: Int(volume.rounded()),
                  pitch: Int(pitch.rounded()),
                  oralLevel: oralLevel,
                  timeoutSeconds: baseConfig.timeoutSeconds)
    }

    /// 设置变更：立刻重建 provider（下次合成即生效），存盘 debounce
    /// 0.4s 合并连续拖动，存盘失败静默忽略（仅丢失本次偏好持久化，
    /// 不打断使用）。
    private func settingsChanged() {
        let config = currentConfig
        provider = makeProvider(config)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            try? self?.settingsStore.save(config)
        }
    }

    var canCancel: Bool {
        if case .synthesizing = state { return synthesisTask != nil }
        return false
    }

    /// 合成并自动开始播放。重复点击会取消上一次。
    /// 合成并播放指定文本。`text` 缺省读 `inputText`（向后兼容）；
    /// 主窗口"朗读输入/朗读结果"按钮直接传对应文本，不再依赖
    /// TTS 独立输入框（已移除）。空白文本静默不合成。
    func synthesizeAndPlay(text overrideText: String? = nil) {
        synthesisTask?.cancel()
        stopPlayback()
        let text = (overrideText ?? inputText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { state = .idle; return }
        // 讯飞合成会吞掉首字（首帧建流时第一个音被截）。送合成前
        // 在文本最前面垫 3 个空格当"起跑缓冲"，让首字完整发出；
        // 仅影响送 provider 的副本，不动 inputText / 不进笔记。
        let synthText = "   " + text
        state = .synthesizing
        synthesisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.provider.synthesize(synthText)
                try Task.checkCancellation()
                try self.loadAndPlay(result)
            } catch let error as AgentError {
                self.state = .failure(error.category)
            } catch is CancellationError {
                self.state = .idle
            } catch {
                self.state = .failure(.unknown)
            }
        }
    }

    /// 划词朗读用：合成 → MP3 落盘缓存目录 → 播放 → 返回 file URL
    /// （笔记插链接用）。与 `synthesizeAndPlay` 同管线（含垫 3 空格
    /// 防吞字），但 await 完成并把文件 URL 交回调用方。失败返回 nil
    /// 并把 `state` 置 `.failure`（UI 可见）。
    func synthesizeSaveAndPlay(text: String) async -> URL? {
        synthesisTask?.cancel()
        stopPlayback()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { state = .idle; return nil }
        state = .synthesizing
        do {
            let result = try await provider.synthesize("   " + trimmed)
            let url = AppComposition.ttsAudioCacheDirectory()
                .appendingPathComponent("\(UUID().uuidString).mp3")
            try result.data.write(to: url, options: .atomic)
            try loadAndPlay(result)
            return url
        } catch let error as AgentError {
            state = .failure(error.category)
            return nil
        } catch {
            state = .failure(.unknown)
            return nil
        }
    }

    func cancelSynthesis() {
        synthesisTask?.cancel()
        synthesisTask = nil
        state = .idle
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    /// 拖动进度条后跳转（fraction 0–1）。
    func seek(toFraction fraction: Double) {
        guard let player, durationSeconds > 0 else { return }
        let clamped = min(max(fraction, 0), 1)
        player.currentTime = clamped * durationSeconds
        progress = clamped
    }

    // MARK: - Internals

    private func loadAndPlay(_ result: AudioResult) throws {
        let player: AVAudioPlayer
        do {
            // 讯飞 aue=lame → MP3，AVAudioPlayer 可直接解码，无需 WAV 头。
            player = try AVAudioPlayer(data: result.data, fileTypeHint: "mp3")
        } catch {
            state = .failure(.providerRejected)
            return
        }
        player.delegate = self
        // enableRate 必须在 prepareToPlay 之前打开，之后改 rate 才会
        // 走 AVFoundation 的时间拉伸（不变调）。
        player.enableRate = true
        player.prepareToPlay()
        player.rate = Float(playbackRate)
        self.player = player
        durationSeconds = player.duration
        progress = 0
        state = .ready
        player.play()
        isPlaying = true
        startTicker()
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player,
                      self.durationSeconds > 0 else { return }
                self.progress = player.currentTime / self.durationSeconds
            }
        }
    }

    private func stopPlayback() {
        ticker?.invalidate()
        ticker = nil
        player?.stop()
        player = nil
        isPlaying = false
        progress = 0
        durationSeconds = 0
    }
}

extension TTSPlaybackViewModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer,
                                                 successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isPlaying = false
            self.progress = flag ? 1 : self.progress
            self.ticker?.invalidate()
            self.ticker = nil
        }
    }
}
