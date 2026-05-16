import Foundation

/// `ResultModel` 的最小 JSONL 持久化：一行一条 JSON，追加写入、整文件读取。
///
/// 编码契约与 TC 契约层一致：snake_case + `.iso8601`（不含亚秒，时间精度
/// 到秒）。文件路径由调用方注入（生产解析 Application Support，单测注入
/// 临时目录），本类型不感知具体位置。
///
/// 写入失败时不丢数据：失败记录留在内存缓冲（`bufferedFailures`）并抛
/// `AgentError(.persistence)`，由上层决定是否展示/重试。失败重试与缓冲
/// 回刷属 T12 硬化范围，此处不做。
final class JSONLResultStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var buffered: [ResultModel] = []

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 写入失败时内存保留的记录（按写入顺序）。
    var bufferedFailures: [ResultModel] {
        lock.lock(); defer { lock.unlock() }
        return buffered
    }

    /// 追加一条记录。失败时记录进内存缓冲并抛 `AgentError(.persistence)`。
    func append(_ record: ResultModel) throws {
        lock.lock()
        defer { lock.unlock() }
        do {
            var line = try JSONLResultStore.makeEncoder().encode(record)
            // JSONL 一行一对象，禁止内部换行；JSONEncoder 默认无 pretty，
            // 单行成立，仅追加行分隔符。
            line.append(0x0A)
            try writeAppending(line)
        } catch let error as AgentError {
            buffered.append(record)
            throw error
        } catch {
            buffered.append(record)
            throw AgentError(category: .persistence,
                             isRetriable: true,
                             diagnosticMessage: "jsonl encode/write failed")
        }
    }

    /// 读取全部记录。空文件返回空数组；某行解码失败抛 `.persistence`
    /// （MVP 不静默跳过损坏行，避免隐藏数据损坏；容错属 T12）。
    func readAll() throws -> [ResultModel] {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw AgentError(category: .persistence,
                             diagnosticMessage: "jsonl read failed")
        }
        guard !data.isEmpty else { return [] }
        let decoder = JSONLResultStore.makeDecoder()
        var results: [ResultModel] = []
        for lineData in data.split(separator: 0x0A) where !lineData.isEmpty {
            do {
                results.append(try decoder.decode(ResultModel.self, from: Data(lineData)))
            } catch {
                throw AgentError(category: .persistence,
                                 diagnosticMessage: "jsonl corrupt line")
            }
        }
        return results
    }

    private func writeAppending(_ data: Data) throws {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) {
            guard fm.createFile(atPath: fileURL.path, contents: nil) else {
                throw AgentError(category: .persistence,
                                 isRetriable: true,
                                 diagnosticMessage: "jsonl create failed")
            }
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
