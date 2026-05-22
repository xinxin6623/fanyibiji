import AVFoundation
import SwiftUI

/// 词典结果卡（仿截图：词头大字 + 中译聚合 + 美/英 IPA + 发音按钮 +
/// 考试标签 chips + 词性释义段 + 变形）。
///
/// 发音 MP3 走 `AVPlayer` 流播（远程 URL 直接喂，无需落盘）。播放器
/// 实例随 View 生命周期，单卡片同时只播一个声道——切按钮时先停旧的。
///
/// 词头大字**双击**保存到知识库(~/knowledge/words/<word>.md),反馈条
/// 在右上角 2 秒淡出。详见 [[project_2026-05-22_dictionary-channel]]。
struct DictionaryCardView: View {
    let entry: DictionaryEntry
    /// 词卡 store 可空(测试或未注入时不暴露双击保存)。
    let wordStore: WordCardStore?

    /// AVPlayer 用 class wrapper 持有，避免 View 重建时丢音；
    /// `@StateObject` 保证整个卡片生命周期内唯一。
    @StateObject private var audio = DictionaryAudioPlayer()

    /// 保存反馈条文本(nil = 不显示),2 秒后自动清零。
    @State private var savedHint: String?

    init(entry: DictionaryEntry, wordStore: WordCardStore? = nil) {
        self.entry = entry
        self.wordStore = wordStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            if !entry.examTags.isEmpty { examTagsRow }
            if !entry.senses.isEmpty { sensesBlock }
            if !entry.forms.isEmpty { formsBlock }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(ClaudeTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(ClaudeTheme.separator, lineWidth: 0.5)
        )
        .overlay(alignment: .topTrailing) {
            if let hint = savedHint {
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(ClaudeTheme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(ClaudeTheme.background)
                    )
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 头部：词头 + 中译 + 音标

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 词头不开 textSelection:让位给「双击保存」手势,避免双击
            // 触发文本选中。需要复制的话用「释义」段(下面有 .enabled)。
            Text(entry.headword)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(ClaudeTheme.primaryText)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { saveToKnowledgeBase() }
                .help("dictionary.save_hint")

            if let summary = entry.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 15))
                    .foregroundStyle(ClaudeTheme.primaryText)
                    .textSelection(.enabled)
            }

            phoneticsRow
        }
    }

    @ViewBuilder
    private var phoneticsRow: some View {
        let hasUS = entry.usIPA != nil || entry.usAudioURL != nil
        let hasUK = entry.ukIPA != nil || entry.ukAudioURL != nil
        let hasGeneric = !hasUS && !hasUK
            && (entry.audioURL != nil)

        VStack(alignment: .leading, spacing: 4) {
            if hasUS {
                phoneticLine(label: "美",
                             ipa: entry.usIPA,
                             audio: entry.usAudioURL)
            }
            if hasUK {
                phoneticLine(label: "英",
                             ipa: entry.ukIPA,
                             audio: entry.ukAudioURL)
            }
            if hasGeneric {
                phoneticLine(label: "", ipa: nil, audio: entry.audioURL)
            }
        }
    }

    private func phoneticLine(label: String,
                              ipa: String?,
                              audio: String?) -> some View {
        HStack(spacing: 8) {
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(ClaudeTheme.secondaryText)
            }
            if let ipa, !ipa.isEmpty {
                Text("/ \(ipa) /")
                    .font(.system(size: 14, design: .default))
                    .foregroundStyle(ClaudeTheme.primaryText)
                    .textSelection(.enabled)
            }
            if let audio, !audio.isEmpty {
                Button {
                    audio_play(audio)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 14))
                        .foregroundStyle(ClaudeTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // 命名前缀避开 SwiftUI body 的 `audio` 实例引用歧义。
    private func audio_play(_ url: String) {
        audio.play(urlString: url)
    }

    /// 词头双击触发:把当前 entry 存为 ~/knowledge/words/<word>.md
    /// (与 [[project_2026-05-22_dictionary-channel]] 一致),反馈条 2 秒淡出。
    /// 未注入 wordStore 时静默忽略(测试或精简组合)。
    private func saveToKnowledgeBase() {
        guard let store = wordStore else { return }
        do {
            let url = try store.save(entry)
            withAnimation(.easeInOut(duration: 0.2)) {
                savedHint = "✓ 已存入 " + url.lastPathComponent
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(.easeInOut(duration: 0.3)) {
                    savedHint = nil
                }
            }
        } catch {
            withAnimation(.easeInOut(duration: 0.2)) {
                savedHint = "✕ 保存失败"
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(.easeInOut(duration: 0.3)) {
                    savedHint = nil
                }
            }
        }
    }

    // MARK: - 考试标签 chips

    private var examTagsRow: some View {
        HStack(spacing: 6) {
            ForEach(entry.examTags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ClaudeTheme.secondaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(ClaudeTheme.separator, lineWidth: 0.5)
                    )
            }
        }
    }

    // MARK: - 词性释义

    private var sensesBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(entry.senses.enumerated()), id: \.offset) { _, s in
                senseRow(s)
            }
        }
    }

    private func senseRow(_ sense: DictionaryEntry.Sense) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let pos = sense.partOfSpeech, !pos.isEmpty {
                Text(pos)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(ClaudeTheme.secondaryText)
                    .frame(minWidth: 28, alignment: .leading)
            }
            Text(sense.gloss)
                .font(.system(size: 14))
                .foregroundStyle(ClaudeTheme.primaryText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 变形

    private var formsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(entry.forms.enumerated()), id: \.offset) { _, f in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(f.name):")
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudeTheme.secondaryText)
                    Text(f.words.joined(separator: ", "))
                        .font(.system(size: 13))
                        .foregroundStyle(ClaudeTheme.primaryText)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

/// 远程 MP3 流播。`AVPlayer` 即开即播,旧实例先 pause 释放,避免叠音。
@MainActor
final class DictionaryAudioPlayer: ObservableObject {
    private var player: AVPlayer?

    func play(urlString: String) {
        guard let url = URL(string: urlString) else { return }
        player?.pause()
        let p = AVPlayer(url: url)
        player = p
        p.play()
    }
}
