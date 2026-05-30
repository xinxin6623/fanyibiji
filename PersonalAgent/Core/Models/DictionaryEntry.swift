import Foundation

/// 单词词典查询结果（YoudaoDictProvider 等填充）。
///
/// 字段按 James 截图必需项最小集：词头/IPA(美英)/发音 URL/词性释义/
/// 变形/考试标签。所有副字段都可缺省——有道接口对短语(如 "look up")
/// 没有 us/uk 拆分，只回 speech；对 ce(中→英)分支无 examType。
struct DictionaryEntry: Codable, Sendable, Equatable {
    /// 词性释义对。`partOfSpeech` 可空(部分人名条目无 pos)。
    struct Sense: Codable, Sendable, Equatable {
        let partOfSpeech: String?
        let gloss: String
    }

    /// 词形变化(复数/比较级/最高级/过去式…)。`name` 中文标签,`words` 形态
    /// 列表(有道用「或」分隔多形,这里已拆好)。
    struct Form: Codable, Sendable, Equatable {
        let name: String
        let words: [String]
    }

    /// 词头(原文)。
    let headword: String
    /// 简要中译聚合(取 trs 首条或 fanyi,卡片副标题用)。
    let summary: String?
    /// 美式音标(不含外层 / /),如 `ˈsuːpərvaɪzər`。
    let usIPA: String?
    /// 英式音标。
    let ukIPA: String?
    /// 美音 MP3 直链(可空,无音频时不渲染按钮)。
    let usAudioURL: String?
    /// 英音 MP3 直链。
    let ukAudioURL: String?
    /// 通用发音 URL(短语/中文等无美英拆分时填这里,渲染单一播放按钮)。
    let audioURL: String?
    /// 词性 → 释义清单。
    let senses: [Sense]
    /// 变形列表。
    let forms: [Form]
    /// 考试标签(CET4/CET6/IELTS…),来自 ec.examType,无则空。
    let examTags: [String]
    /// 数据源标识(provider id),供失败溯源。
    let source: String
}

extension DictionaryEntry {
    /// 整张词典卡转 Markdown,末尾带「有道详解」外链。给「插入笔记」
    /// 按钮用——让用户能把词典查询结果当一段引用直接落进笔记里。
    /// 详见 [[project_2026-05-22_dictionary-channel]]。
    func toMarkdownCard() -> String {
        var lines: [String] = ["### \(headword)"]

        let us = usIPA.flatMap { $0.isEmpty ? nil : $0 }
        let uk = ukIPA.flatMap { $0.isEmpty ? nil : $0 }
        switch (us, uk) {
        case let (u?, k?):
            lines.append("美 / \(u) /  ·  英 / \(k) /")
        case let (u?, nil):
            lines.append("/ \(u) /")
        case let (nil, k?):
            lines.append("/ \(k) /")
        case (nil, nil):
            break
        }

        if !senses.isEmpty {
            for s in senses {
                if let pos = s.partOfSpeech, !pos.isEmpty {
                    lines.append("- **\(pos)** \(s.gloss)")
                } else {
                    lines.append("- \(s.gloss)")
                }
            }
        } else if let summary, !summary.isEmpty {
            lines.append(summary)
        }

        if !forms.isEmpty {
            for f in forms {
                lines.append("**\(f.name)：** \(f.words.joined(separator: ", "))")
            }
        }

        let encoded = headword.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? headword
        lines.append("[有道详解 →](https://www.youdao.com/result?word=\(encoded)&lang=en)")

        return lines.joined(separator: "\n")
    }

    /// TTS 朗读文本:词头 + 简要中译。避免把 markdown 标记和 URL
    /// 一并念出来(纯朗读 toMarkdownCard() 会非常难听)。
    func spokenSummary() -> String {
        if let summary, !summary.isEmpty {
            return "\(headword)。\(summary)"
        }
        return headword
    }
}
