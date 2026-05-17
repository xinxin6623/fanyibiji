import Foundation

/// 多草稿持久化:`notes/` 目录下每草稿一个 `.md`,配套一份记录
/// 「该草稿引用过哪些来源 result id」的 sidecar(原料包 A 源追用),
/// 外加一个 `manifest.json` 记 Tab 顺序/标题缓存/当前选中。
///
/// 与 `results.jsonl` 完全分离——这里是用户手敲的笔记草稿(暂存)。
/// 写入用「临时文件 + 原子替换」避免半截写坏(笔记丢失代价高)。
/// 失败抛 `AgentError(.persistence)`,由上层决定提示/重试。
///
/// 不做旧 `note-draft.md` 迁移(James 明确不怕丢):全新 notes/ 体系。
final class NoteDraftStore: @unchecked Sendable {

    /// manifest 里一条草稿的元信息(顺序由数组位置决定)。
    struct Entry: Codable, Sendable, Equatable {
        let id: UUID
        var title: String     // 草稿首行缓存,空 → 由上层显示「未命名」
    }

    struct Manifest: Codable, Sendable, Equatable {
        var entries: [Entry]
        var selectedID: UUID?
    }

    private let notesDir: URL
    private let lock = NSLock()

    /// - Parameter notesDirectory: `.../com.james.personalagent/notes`
    init(notesDirectory: URL) {
        self.notesDir = notesDirectory
    }

    private func draftURL(_ id: UUID) -> URL {
        notesDir.appendingPathComponent("draft-\(id.uuidString).md")
    }
    private func sidecarURL(_ id: UUID) -> URL {
        notesDir.appendingPathComponent(".draft-\(id.uuidString).sourcemap.json")
    }
    private var manifestURL: URL {
        notesDir.appendingPathComponent("manifest.json")
    }

    // MARK: - 草稿正文

    /// 读草稿正文。不存在/空 → 空串(非错误:新草稿即空白)。
    func load(id: UUID) throws -> String {
        lock.lock(); defer { lock.unlock() }
        let url = draftURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return "" }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw AgentError(category: .persistence,
                             diagnosticMessage: "note draft read failed")
        }
    }

    /// 原子写草稿正文。
    func save(id: UUID, text: String) throws {
        lock.lock(); defer { lock.unlock() }
        try atomicWrite(text.data(using: .utf8) ?? Data(), to: draftURL(id))
    }

    // MARK: - sidecar(referencedResultIDs)

    /// 读该草稿引用过的来源 result id 集合。缺失/损坏 → 空集合(降级,
    /// 不崩;原料包仍可靠 B 文本兜底)。
    func loadSourceIDs(id: UUID) -> Set<UUID> {
        lock.lock(); defer { lock.unlock() }
        let url = sidecarURL(id)
        guard let data = try? Data(contentsOf: url),
              let arr = try? JSONDecoder().decode([UUID].self, from: data)
        else { return [] }
        return Set(arr)
    }

    /// 原子写 sidecar。失败按 .persistence 抛(上层可降级忽略)。
    func saveSourceIDs(id: UUID, ids: Set<UUID>) throws {
        lock.lock(); defer { lock.unlock() }
        let data = try JSONEncoder().encode(Array(ids))
        try atomicWrite(data, to: sidecarURL(id))
    }

    // MARK: - manifest

    /// 读 manifest。不存在/损坏 → 扫 notes/ 目录重建(降级容错:不至于
    /// 因 manifest 坏掉就看不到已有草稿)。
    func loadManifest() -> Manifest {
        lock.lock(); defer { lock.unlock() }
        if let data = try? Data(contentsOf: manifestURL),
           let m = try? JSONDecoder().decode(Manifest.self, from: data) {
            return m
        }
        return rebuiltManifestFromDisk()
    }

    func saveManifest(_ manifest: Manifest) throws {
        lock.lock(); defer { lock.unlock() }
        let data = try JSONEncoder().encode(manifest)
        try atomicWrite(data, to: manifestURL)
    }

    /// 列举 notes/ 下全部草稿文件 id(供「历史草稿」列表去重用)。
    func allDraftIDs() -> [UUID] {
        lock.lock(); defer { lock.unlock() }
        return scanDiskDraftIDs()
    }

    /// 删除草稿正文 + sidecar。关闭 Tab **不**调用(关闭=留盘);
    /// 保留给未来「显式清理历史草稿」用。
    func delete(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: draftURL(id))
        try? FileManager.default.removeItem(at: sidecarURL(id))
    }

    // MARK: - 内部

    private func scanDiskDraftIDs() -> [UUID] {
        guard let names = try? FileManager.default.contentsOfDirectory(
            atPath: notesDir.path) else { return [] }
        return names.compactMap { name -> UUID? in
            guard name.hasPrefix("draft-"), name.hasSuffix(".md") else { return nil }
            let uuid = name.dropFirst("draft-".count).dropLast(".md".count)
            return UUID(uuidString: String(uuid))
        }
    }

    private func rebuiltManifestFromDisk() -> Manifest {
        let ids = scanDiskDraftIDs()
        let entries = ids.map { id -> Entry in
            let first = (try? String(contentsOf: draftURL(id), encoding: .utf8))?
                .split(separator: "\n").first.map(String.init) ?? ""
            return Entry(id: id, title: first)
        }
        return Manifest(entries: entries, selectedID: entries.first?.id)
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let tmp = dir.appendingPathComponent(
                ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
            try data.write(to: tmp, options: .atomic)
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
        } catch {
            throw AgentError(category: .persistence,
                             isRetriable: true,
                             diagnosticMessage: "note store write failed")
        }
    }
}
