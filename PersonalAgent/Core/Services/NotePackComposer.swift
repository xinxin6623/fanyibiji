import Foundation

/// 「笔记原料包」合成器——纯函数,零 IO 零网络,易单测。
///
/// 输入:当前草稿全文 + 该草稿引用过的来源 result id 集合(A 源追)
///       + 全量 `ResultModel`(来自 results.jsonl)。
/// 输出:单个 Markdown 字符串,交下游知识库 Claude 做结构化/复利。
///
/// 相关性判定 = C(A 为主 B 兜底,已与 James 对齐):
///  - A 源追:`referencedResultIDs` 里的 id → 取对应 jsonl 条目(精确)
///  - B 文本兜底:草稿全文里**整段包含**某条译文文本 → 补(用户手敲/
///    粘贴、未走「插入」按钮的译文)
///  - A∪B 去重(按 result id),清洗:只留「原文 → 译文」,丢
///    id/时间戳/provider/tags;`error`/空内容/audio 条目排除。
enum NotePackComposer {

    /// 一条清洗后的翻译条目(给 LLM 读的最小信息)。
    struct Pair: Equatable {
        let source: String   // 原文(ResultModel.sourceText)
        let translation: String  // 译文(ResultContent.translation/​text)
        let viaSourceTracking: Bool  // true=A 命中,false=仅 B 文本兜底
    }

    /// 合成原料包 Markdown。
    /// - Parameters:
    ///   - draft: 草稿全文(原样,含用户手动编辑)
    ///   - referencedResultIDs: 该草稿「插入到编辑区」记录的来源 id(A)
    ///   - allResults: results.jsonl 全量读出
    ///   - now: 标题时间戳(注入以便单测可复现)
    static func compose(draft: String,
                        referencedResultIDs: Set<UUID>,
                        allResults: [ResultModel],
                        now: Date = Date()) -> String {
        let pairs = relevantPairs(draft: draft,
                                  referencedResultIDs: referencedResultIDs,
                                  allResults: allResults)

        let stamp = Self.stampFormatter.string(from: now)
        var out = "# 笔记原料包 · \(stamp)\n\n"

        out += "## 草稿\n"
        out += (draft.isEmpty ? "_(空草稿)_" : draft)
        out += "\n\n"

        out += "## 相关翻译历史\n"
        if pairs.isEmpty {
            out += "_(无相关翻译历史)_\n"
            return out
        }
        let aCount = pairs.filter { $0.viaSourceTracking }.count
        let bCount = pairs.count - aCount
        out += "> 共 \(pairs.count) 条,A源追 \(aCount) 条 / B文本兜底 \(bCount) 条\n\n"
        for (i, p) in pairs.enumerated() {
            out += "\(i + 1). 原文:\(p.source)\n"
            out += "   译文:\(p.translation)\n"
        }
        return out
    }

    /// A∪B 去重后的相关条目(导出顺序:按 allResults 原始顺序稳定)。
    /// 暴露为 internal 便于单测直接断言配对,不必解析 Markdown。
    static func relevantPairs(draft: String,
                              referencedResultIDs: Set<UUID>,
                              allResults: [ResultModel]) -> [Pair] {
        var seen = Set<UUID>()
        var pairs: [Pair] = []
        for r in allResults {
            guard seen.contains(r.id) == false else { continue }
            // 清洗:失败条目、audio 内容排除。译文实际以 `.text` 落盘
            // (见 ContentQueryViewModel:翻译/LLM 结果均 content=.text),
            // `.translation` case 仅理论存在,一并接受;audio 不是文本翻译。
            guard r.error == nil else { continue }
            let text: String
            switch r.content {
            case let .text(t): text = t
            case let .translation(t, _, _): text = t
            case .audio: continue
            }
            guard text.isEmpty == false else { continue }
            // 无原文的历史条目(旧 jsonl 或非翻译查询)对「原文→译文」
            // 无价值,跳过。
            guard let source = r.sourceText, source.isEmpty == false else { continue }

            let hitA = referencedResultIDs.contains(r.id)
            // B:草稿整段包含该译文文本(整段命中,避免短译文误中一片)。
            let hitB = !text.isEmpty && draft.contains(text)
            guard hitA || hitB else { continue }

            seen.insert(r.id)
            pairs.append(Pair(source: source,
                              translation: text,
                              viaSourceTracking: hitA))
        }
        return pairs
    }

    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()
}
