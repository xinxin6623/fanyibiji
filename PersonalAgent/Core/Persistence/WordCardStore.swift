import Foundation

/// 词卡 Markdown 写入与合并：
///   ~/knowledge/words/<word>.md       — 单词卡(frontmatter + 渲染正文)
///
/// 设计：
/// - 文件名小写归一(Supervisor → supervisor.md)避免重复建条;
/// - 已存在文件**保留正文**(用户可能改过批注),仅更新 frontmatter 里
///   的 lookup_count/last_saved/source 等"机器字段"——以正文里的
///   `<!-- agent:meta -->`...`<!-- /agent:meta -->` 标记包裹,合并仅
///   动这一块;
/// - 音频不再落盘,frontmatter 和正文里保留远程 MP3 链接即可
///   (2026-05-30 改:用户决定只存链接,避免大量小 mp3 散落)。
///
/// AGENTS 边界：与 JSONLResultStore 平行,只负责"用户主动归档"的快照,
/// 不替代 results.jsonl 完整时间线。失败上抛 AgentError 供 UI 友好提示。
struct WordCardStore: Sendable {
    let rootDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL,
         fileManager: FileManager = .default) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    /// 写入(或合并)一个 DictionaryEntry。返回最终落盘的 md 文件 URL,
    /// 供 UI 反馈条显示路径。
    @discardableResult
    func save(_ entry: DictionaryEntry,
              now: Date = Date()) throws -> URL {
        try ensureDirectories()
        let slug = Self.slug(entry.headword)
        let mdURL = rootDirectory.appendingPathComponent("\(slug).md")

        let existing = (try? loadMeta(at: mdURL)) ?? Meta(lookupCount: 0,
                                                          firstSaved: now)
        let newMeta = Meta(
            lookupCount: existing.lookupCount + 1,
            firstSaved: existing.firstSaved,
            lastSaved: now
        )

        let content: String
        if fileManager.fileExists(atPath: mdURL.path) {
            // 已存在:仅替换 <!-- agent:meta --> 块,正文不动。
            let raw = try String(contentsOf: mdURL, encoding: .utf8)
            content = Self.replaceMetaBlock(in: raw, with: render(entry: entry,
                                                                   meta: newMeta,
                                                                   bodyOnly: false))
        } else {
            content = render(entry: entry, meta: newMeta, bodyOnly: false)
        }
        do {
            try content.write(to: mdURL, atomically: true, encoding: .utf8)
        } catch {
            throw AgentError(category: .persistence,
                             diagnosticMessage: "word card write failed: \(error)")
        }
        return mdURL
    }

    // MARK: - 目录

    private func ensureDirectories() throws {
        do {
            try fileManager.createDirectory(at: rootDirectory,
                                            withIntermediateDirectories: true)
        } catch {
            throw AgentError(category: .persistence,
                             diagnosticMessage: "words dir create failed: \(error)")
        }
    }

    // MARK: - 文件名

    /// 单词归一为文件名:小写 + 仅保留 [a-z0-9-_]，其它统统 `-`。
    /// 短语 "look up" → "look-up.md"。中文等其它字符进文件名也允许,
    /// 但 macOS 文件系统会保留——保险起见去掉 / : 等保留字。
    static func slug(_ headword: String) -> String {
        let lower = headword.lowercased()
        var out = ""
        for ch in lower {
            if ch.isLetter || ch.isNumber || ch == "-" || ch == "_" {
                out.append(ch)
            } else if ch == " " || ch == "/" || ch == "\\" || ch == ":" {
                out.append("-")
            } else {
                out.append(ch)
            }
        }
        // 去前后 -,避免 "-good.md"。
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .ifEmpty(fallback: "unknown")
    }

    // MARK: - meta 块

    struct Meta {
        var lookupCount: Int
        var firstSaved: Date
        var lastSaved: Date?

        init(lookupCount: Int, firstSaved: Date, lastSaved: Date? = nil) {
            self.lookupCount = lookupCount
            self.firstSaved = firstSaved
            self.lastSaved = lastSaved
        }
    }

    private static let metaOpen = "<!-- agent:meta -->"
    private static let metaClose = "<!-- /agent:meta -->"

    /// 从已有 md 提取 lookup_count / first_saved。仅扫 frontmatter 简单
    /// `key: value` 形式;失败回退 nil(调用方按首写处理)。
    func loadMeta(at url: URL) throws -> Meta {
        let raw = try String(contentsOf: url, encoding: .utf8)
        // frontmatter: --- ... ---
        guard raw.hasPrefix("---") else {
            throw AgentError(category: .persistence,
                             diagnosticMessage: "missing frontmatter")
        }
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
        var lookup = 0
        var first = Date()
        var inFM = false
        for line in lines {
            if line == "---" {
                if inFM { break }
                inFM = true; continue
            }
            guard inFM else { continue }
            if line.hasPrefix("lookup_count:") {
                let v = line.dropFirst("lookup_count:".count)
                    .trimmingCharacters(in: .whitespaces)
                lookup = Int(v) ?? 0
            } else if line.hasPrefix("first_saved:") {
                let v = line.dropFirst("first_saved:".count)
                    .trimmingCharacters(in: .whitespaces)
                if let d = Self.isoFormatter.date(from: v) { first = d }
            }
        }
        return Meta(lookupCount: lookup, firstSaved: first)
    }

    static func replaceMetaBlock(in raw: String, with rendered: String) -> String {
        // 直接全文重写:已合并好 meta+body,正文保留靠 mergeBody 处理过的
        // rendered。这里实际场景下我们已用 render(bodyOnly:false) 覆盖,
        // 但为了"用户改过的正文不丢",看是否有 <!-- agent:body --> 标记:
        // 有则仅替换 frontmatter 段,正文照搬。
        let bodyOpen = "<!-- agent:body -->"
        let bodyClose = "<!-- /agent:body -->"
        if let bOpen = raw.range(of: bodyOpen),
           let bClose = raw.range(of: bodyClose) {
            // 保留 raw 里 bodyOpen..bodyClose 之间的用户改动,
            // 仅替换 frontmatter+meta 注释段。
            let userBody = String(raw[bOpen.upperBound..<bClose.lowerBound])
            // rendered 里也有同样标记,把它的 body 段替成 userBody。
            if let rOpen = rendered.range(of: bodyOpen),
               let rClose = rendered.range(of: bodyClose) {
                var merged = rendered
                merged.replaceSubrange(rOpen.upperBound..<rClose.lowerBound,
                                       with: userBody)
                return merged
            }
        }
        return rendered
    }

    // MARK: - 渲染

    private func render(entry: DictionaryEntry, meta: Meta, bodyOnly: Bool) -> String {
        var out = ""

        // frontmatter
        out += "---\n"
        out += "word: \(entry.headword)\n"
        if let s = entry.summary { out += "summary: \(yamlString(s))\n" }
        if let v = entry.usIPA { out += "us_ipa: \(yamlString(v))\n" }
        if let v = entry.ukIPA { out += "uk_ipa: \(yamlString(v))\n" }
        if let v = entry.usAudioURL { out += "us_audio: \(yamlString(v))\n" }
        if let v = entry.ukAudioURL { out += "uk_audio: \(yamlString(v))\n" }
        if let v = entry.audioURL { out += "audio: \(yamlString(v))\n" }
        if !entry.examTags.isEmpty {
            out += "tags: [\(entry.examTags.joined(separator: ", "))]\n"
        }
        out += "source: \(entry.source)\n"
        out += "first_saved: \(Self.isoFormatter.string(from: meta.firstSaved))\n"
        out += "last_saved: \(Self.isoFormatter.string(from: meta.lastSaved ?? meta.firstSaved))\n"
        out += "lookup_count: \(meta.lookupCount)\n"
        out += "review_count: 0\n"
        out += "last_reviewed: null\n"
        out += "---\n\n"

        // body：用 <!-- agent:body --> 包起来,合并时识别用户改动。
        out += "<!-- agent:body -->\n"
        out += "# \(entry.headword)\n\n"
        if let s = entry.summary { out += "\(s)\n\n" }

        var phLines: [String] = []
        if let us = entry.usIPA {
            let line = "- 美 /\(us)/" +
                (entry.usAudioURL.map { " [🔊](\($0))" } ?? "")
            phLines.append(line)
        }
        if let uk = entry.ukIPA {
            let line = "- 英 /\(uk)/" +
                (entry.ukAudioURL.map { " [🔊](\($0))" } ?? "")
            phLines.append(line)
        }
        if !phLines.isEmpty {
            out += phLines.joined(separator: "\n") + "\n\n"
        }

        if !entry.examTags.isEmpty {
            out += "**考试标签**: " + entry.examTags.joined(separator: ", ") + "\n\n"
        }

        if !entry.senses.isEmpty {
            out += "## 释义\n\n"
            for s in entry.senses {
                if let pos = s.partOfSpeech {
                    out += "- **\(pos)** \(s.gloss)\n"
                } else {
                    out += "- \(s.gloss)\n"
                }
            }
            out += "\n"
        }

        if !entry.forms.isEmpty {
            out += "## 变形\n\n"
            for f in entry.forms {
                out += "- \(f.name): \(f.words.joined(separator: ", "))\n"
            }
            out += "\n"
        }

        out += "<!-- /agent:body -->\n"
        _ = bodyOnly // 预留 hook
        return out
    }

    private func yamlString(_ s: String) -> String {
        // 内含特殊字符则加引号转义。简化版,够 IPA/URL/中文用。
        if s.contains(":") || s.contains("#") || s.contains("\"")
            || s.hasPrefix(" ") || s.hasSuffix(" ") {
            let esc = s.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(esc)\""
        }
        return s
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

}

private extension String {
    func ifEmpty(fallback: String) -> String { isEmpty ? fallback : self }
}
