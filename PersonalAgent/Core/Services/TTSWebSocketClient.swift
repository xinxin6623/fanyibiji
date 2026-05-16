import Foundation
import CryptoKit

/// 讯飞 TTS 的网络出口抽象：隔离 `URLSessionWebSocketTask`，便于单测
/// 注入桩覆盖成功/超时/取消/鉴权/网络各分支，不依赖真实网络。
///
/// 语义为「攒整段」：建连 → 发一帧合成请求 → 持续收帧直到
/// `data.status == 2`，把所有 `data.audio` 片段按序拼成完整音频。
/// 不在此处翻译错误，统一交 provider 映射成 `AgentError`。
protocol TTSWebSocketClient: Sendable {
    /// 建连并完成一次完整合成会话，返回拼好的 MP3 字节。
    /// - Parameter requestFrame: 已编码好的首帧 JSON（common/business/data）。
    func synthesize(url: URL,
                     requestFrame: Data,
                     timeoutSeconds: Double) async throws -> Data
}

/// 生产实现：`URLSessionWebSocketTask` 攒整段。
///
/// 超时由外层 `withThrowingTaskGroup` + 计时任务承载（WebSocket task
/// 无 per-message 超时）；Swift Task 取消会传导到 receive。错误保持
/// 网络层无业务语义，由 provider 统一映射。
struct URLSessionTTSWebSocketClient: TTSWebSocketClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func synthesize(url: URL,
                    requestFrame: Data,
                    timeoutSeconds: Double) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await Self.runSession(session: session,
                                          url: url,
                                          requestFrame: requestFrame)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                throw AgentError(category: .timeout,
                                 isRetriable: true,
                                 diagnosticMessage: "tts websocket timed out")
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw AgentError(category: .network,
                                 isRetriable: true,
                                 diagnosticMessage: "tts websocket produced no result")
            }
            return result
        }
    }

    private static func runSession(session: URLSession,
                                   url: URL,
                                   requestFrame: Data) async throws -> Data {
        let task = session.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .normalClosure, reason: nil) }

        let frameString = String(decoding: requestFrame, as: UTF8.self)
        try await task.send(.string(frameString))

        var collector = TTSFrameCollector()
        while !collector.isComplete {
            try Task.checkCancellation()
            let message = try await task.receive()
            let payload: Data
            switch message {
            case let .string(text):
                payload = Data(text.utf8)
            case let .data(data):
                payload = data
            @unknown default:
                throw AgentError(category: .network,
                                 diagnosticMessage: "unknown websocket frame")
            }
            try collector.ingest(payload)
        }
        return collector.audioData
    }
}

/// 讯飞返回帧的纯逻辑累加器：解析 `code`/`data.audio`/`data.status`，
/// 按序拼接 base64 音频，遇 `code != 0` 抛 `.providerRejected`。
/// 抽成纯结构以便零网络单测覆盖拼接与错误码分支。
struct TTSFrameCollector {
    private(set) var audioData = Data()
    private(set) var isComplete = false

    /// 摄入一帧返回 JSON。
    /// - Throws: `code != 0` → `.providerRejected`（带讯飞错误码）；
    ///           结构非法 → `.providerRejected`。
    mutating func ingest(_ payload: Data) throws {
        guard let root = (try? JSONSerialization.jsonObject(with: payload))
                as? [String: Any] else {
            throw AgentError(category: .providerRejected,
                             diagnosticMessage: "invalid tts frame json")
        }
        let code = (root["code"] as? Int) ?? -1
        guard code == 0 else {
            let message = (root["message"] as? String) ?? "tts rejected"
            // 11201/11202 流控类可重试；鉴权/授权类不可重试。
            let retriable = code == 11201 || code == 11202 || code == 10200
            throw AgentError(category: .providerRejected,
                             isRetriable: retriable,
                             diagnosticMessage: message,
                             providerErrorCode: "XF_\(code)")
        }
        guard let data = root["data"] as? [String: Any] else {
            throw AgentError(category: .providerRejected,
                             diagnosticMessage: "tts frame missing data")
        }
        if let audioB64 = data["audio"] as? String,
           !audioB64.isEmpty,
           let chunk = Data(base64Encoded: audioB64) {
            audioData.append(chunk)
        }
        if (data["status"] as? Int) == 2 {
            isComplete = true
        }
    }
}

/// 讯飞 HMAC-SHA256 鉴权 + 首帧编码的纯函数集合。
///
/// 全部无副作用、不触网，便于单测对签名串与帧结构做确定性断言
/// （传入固定 date 即可复现）。算法对齐官方文档：
/// signature_origin = "host: H\ndate: D\nGET P HTTP/1.1"，
/// signature = base64(HMAC-SHA256(origin, apiSecret))，
/// authorization = base64(`api_key="K", algorithm="hmac-sha256",
/// headers="host date request-line", signature="S"`)。
enum XunfeiTTSAuth {

    /// RFC1123 / GMT 日期串，例：`Thu, 01 Aug 2019 01:53:21 GMT`。
    static func rfc1123Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    /// 由 host/date 配置生成带鉴权 query 的最终 wss URL。
    /// - Throws: host 非法 → `.invalidInput`。
    static func signedURL(host hostUrl: URL,
                          apiKey: String,
                          apiSecret: String,
                          date: Date) throws -> URL {
        guard let host = hostUrl.host else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "invalid tts host")
        }
        let path = hostUrl.path.isEmpty ? "/v2/tts" : hostUrl.path
        let dateString = rfc1123Date(date)

        let signatureOrigin = """
        host: \(host)
        date: \(dateString)
        GET \(path) HTTP/1.1
        """

        let key = SymmetricKey(data: Data(apiSecret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(signatureOrigin.utf8), using: key)
        let signature = Data(mac).base64EncodedString()

        let authorizationOrigin =
            "api_key=\"\(apiKey)\", algorithm=\"hmac-sha256\", "
            + "headers=\"host date request-line\", signature=\"\(signature)\""
        let authorization = Data(authorizationOrigin.utf8).base64EncodedString()

        var components = URLComponents()
        components.scheme = hostUrl.scheme
        components.host = host
        components.path = path
        if let port = hostUrl.port { components.port = port }
        components.queryItems = [
            URLQueryItem(name: "authorization", value: authorization),
            URLQueryItem(name: "date", value: dateString),
            URLQueryItem(name: "host", value: host)
        ]
        guard let url = components.url else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "failed to build signed tts url")
        }
        return url
    }

    /// 首帧请求 JSON：common/business/data。
    /// `aue=lame` → MP3；`tte=UTF8`；`status=2`（流式不支持分段）。
    /// - Throws: 文本空或超 8000 字节 → `.invalidInput`。
    static func requestFrame(appId: String,
                             vcn: String,
                             speed: Int,
                             volume: Int,
                             pitch: Int,
                             text: String) throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "empty tts text")
        }
        let textBytes = Data(trimmed.utf8)
        guard textBytes.count < 8000 else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "tts text exceeds 8000 bytes")
        }

        let body: [String: Any] = [
            "common": ["app_id": appId],
            "business": [
                "aue": "lame",
                "sfl": 1,
                "auf": "audio/L16;rate=16000",
                "vcn": vcn,
                "tte": "UTF8",
                "speed": speed,
                "volume": volume,
                "pitch": pitch
            ],
            "data": [
                "status": 2,
                "text": textBytes.base64EncodedString()
            ]
        ]
        do {
            return try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "failed to encode tts request")
        }
    }
}
