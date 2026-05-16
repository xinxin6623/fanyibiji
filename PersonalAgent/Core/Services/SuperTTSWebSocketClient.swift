import Foundation

/// 讯飞**超拟人**语音合成 WebSocket 客户端（与普通 v2/tts 不同接口）。
///
/// 鉴权完全复用 `XunfeiTTSAuth.signedURL`（同 HMAC-SHA256、同三件套
/// 密钥），仅 host/path 与请求/返回 JSON 结构不同：
/// - 请求：header / parameter(.oral/.tts/.tts.audio) / payload.text
/// - 返回：header.code/status + payload.audio.audio(base64) / status
///
/// 语义同样「攒整段」：发一帧 status=2 文本 → 持续收帧直到
/// `payload.audio.status==2`，按 seq 顺序拼完整 MP3。
protocol SuperTTSWebSocketClient: Sendable {
    func synthesize(url: URL,
                    requestFrame: Data,
                    timeoutSeconds: Double) async throws -> Data
}

/// 生产实现：`URLSessionWebSocketTask` 攒整段（结构同
/// `URLSessionTTSWebSocketClient`，仅帧累加器不同）。
struct URLSessionSuperTTSWebSocketClient: SuperTTSWebSocketClient {
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
                                 diagnosticMessage: "super tts websocket timed out")
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw AgentError(category: .network,
                                 isRetriable: true,
                                 diagnosticMessage: "super tts produced no result")
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

        try await task.send(.string(String(decoding: requestFrame, as: UTF8.self)))

        var collector = SuperTTSFrameCollector()
        while !collector.isComplete {
            try Task.checkCancellation()
            let message = try await task.receive()
            let payload: Data
            switch message {
            case let .string(text): payload = Data(text.utf8)
            case let .data(data):   payload = data
            @unknown default:
                throw AgentError(category: .network,
                                 diagnosticMessage: "unknown websocket frame")
            }
            try collector.ingest(payload)
        }
        return collector.audioData
    }
}

/// 超拟人返回帧的纯逻辑累加器：解析 `header.code`/`payload.audio.audio`
/// /`payload.audio.status`，base64 拼接音频，`code != 0` 抛
/// `.providerRejected`。抽纯结构以便零网络单测。
struct SuperTTSFrameCollector {
    private(set) var audioData = Data()
    private(set) var isComplete = false

    mutating func ingest(_ payload: Data) throws {
        guard let root = (try? JSONSerialization.jsonObject(with: payload))
                as? [String: Any] else {
            throw AgentError(category: .providerRejected,
                             diagnosticMessage: "invalid super tts frame json")
        }
        let header = root["header"] as? [String: Any]
        let code = (header?["code"] as? Int) ?? -1
        guard code == 0 else {
            let message = (header?["message"] as? String) ?? "super tts rejected"
            // 流控/限频类可重试；鉴权/授权类不可重试（与普通 TTS 同策略）。
            let retriable = code == 11200 || code == 11201 || code == 11202
            throw AgentError(category: .providerRejected,
                             isRetriable: retriable,
                             diagnosticMessage: message,
                             providerErrorCode: "XF_\(code)")
        }
        if let p = root["payload"] as? [String: Any],
           let audio = p["audio"] as? [String: Any] {
            if let b64 = audio["audio"] as? String,
               !b64.isEmpty,
               let chunk = Data(base64Encoded: b64) {
                audioData.append(chunk)
            }
            if (audio["status"] as? Int) == 2 { isComplete = true }
        }
        // 兜底：部分实现仅在 header.status==2 标结束。
        if (header?["status"] as? Int) == 2 { isComplete = true }
    }
}

/// 超拟人首帧请求 JSON（header/parameter/payload）。
/// `audio.encoding=lame` → MP3、24k；`text.encoding=utf8`、status=2。
/// 口语化 `parameter.oral`：oral_level + spark_assist（仅 x4/x5 系列）。
enum SuperTTSRequest {
    static func frame(appId: String,
                      vcn: String,
                      speed: Int,
                      volume: Int,
                      pitch: Int,
                      oralLevel: TTSOralLevel,
                      text: String) throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "empty super tts text")
        }
        let textBytes = Data(trimmed.utf8)
        // 超拟人上限 64KB（文档），留余量。
        guard textBytes.count < 60_000 else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "super tts text exceeds 60000 bytes")
        }

        let body: [String: Any] = [
            "header": [
                "app_id": appId,
                "status": 2
            ],
            "parameter": [
                "oral": [
                    "oral_level": oralLevel.rawValue,
                    "spark_assist": 1
                ],
                "tts": [
                    "vcn": vcn,
                    "speed": speed,
                    "volume": volume,
                    "pitch": pitch,
                    "audio": [
                        "encoding": "lame",
                        "sample_rate": 24000,
                        "channels": 1,
                        "bit_depth": 16,
                        "frame_size": 0
                    ]
                ]
            ],
            "payload": [
                "text": [
                    "encoding": "utf8",
                    "compress": "raw",
                    "format": "plain",
                    "status": 2,
                    "seq": 0,
                    "text": textBytes.base64EncodedString()
                ]
            ]
        ]
        do {
            return try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "failed to encode super tts request")
        }
    }
}
