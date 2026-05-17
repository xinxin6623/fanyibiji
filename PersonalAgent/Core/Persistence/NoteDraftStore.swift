import Foundation

/// 笔记暂存草稿的最小持久化：单个 `.md` 纯文本文件，整文件读写。
///
/// 与 `results.jsonl` 完全分离——这里存的是用户手工编辑的笔记草稿
/// （暂存状态）。后续「最终笔记生成」会调 LLM 结构化处理，届时会回
/// 头抓取原始翻译历史，这里只负责草稿本身的读写。
///
/// 写入用「临时文件 + 原子替换」避免半截写坏草稿（笔记是用户手敲的，
/// 丢失代价高，比 JSONL 单条更值得做原子写）。失败抛
/// `AgentError(.persistence)`，由上层决定提示/重试。
final class NoteDraftStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// 读取草稿。文件不存在/为空返回空串（非错误：首次使用即空白）。
    /// 读失败（IO/编码）抛 `.persistence`，不返回脏数据。
    func load() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ""
        }
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            throw AgentError(category: .persistence,
                             diagnosticMessage: "note draft read failed")
        }
    }

    /// 原子写入草稿（临时文件 + 替换）。父目录按需创建。
    /// 失败抛 `AgentError(.persistence, isRetriable: true)`。
    func save(_ text: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let tmpURL = dir.appendingPathComponent(
                ".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
            try text.data(using: .utf8)?.write(to: tmpURL, options: .atomic)
            // 已存在则 replace，否则 move（replaceItem 要求目标存在）。
            if fm.fileExists(atPath: fileURL.path) {
                _ = try fm.replaceItemAt(fileURL, withItemAt: tmpURL)
            } else {
                try fm.moveItem(at: tmpURL, to: fileURL)
            }
        } catch {
            throw AgentError(category: .persistence,
                             isRetriable: true,
                             diagnosticMessage: "note draft write failed")
        }
    }
}
