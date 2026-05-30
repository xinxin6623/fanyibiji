import Foundation
import os.log

/// 豆包/火山 HTTP 一句话 TTS provider（一次 POST，base64 mp3 返回）。
///
/// 消费 `TTSConfigStore.resolve` 产出的 `ResolvedTTSConfig`（不自读
/// Keychain）。`validate()` 仅形状检查、零网络。所有失败统一映射
/// `AgentError`，UI 只按 `category` 分支，不暴露豆包私有错误码（错误码
/// 进 `providerErrorCode` 仅作诊断）。
///
/// 协议要点：
///  - `Authorization: Bearer; <token>`（**冒号后跟分号空格**，是豆包文档要求）；
///  - body 由 `app.{appid,token,cluster}` + `user.uid` + `audio.{voice_type,
///    encoding,speed_ratio,volume_ratio,pitch_ratio}` + `request.{reqid,text,
///    operation:"query"}` 组成；
///  - 返回 `{"code":3000,"data":"<base64 mp3>", ...}`，code != 3000 即失败；
///  - cluster 写死 `volcano_tts`（HTTP 一句话标准服务集群），不暴露给 UI。
struct DoubaoTTSProvider: TTSProvider {
    let id = "doubao-tts"

    private let config: ResolvedTTSConfig
    private let client: LLMHTTPClient
    private let uuid: @Sendable () -> String

    /// 火山引擎 HTTP 一句话 cluster：
    ///  - 「语音合成大模型-字符版」(service 10007) → `volcano_tts`（虽然带
    ///    "大模型"前缀但 cluster 仍是这个，官方命名误导）
    ///  - 「声音复刻大模型」→ `volcano_icl`
    ///  - 基础一句话 (service 8001) → `volcano_tts`
    /// 三类同 cluster 名，区分点是 voice_type，不是 cluster；写死避免误配。
    private static let cluster = "volcano_tts"

    /// Console.app 抓诊断日志用（subsystem=app bundle id, category=DoubaoTTS）。
    /// UI 上 AgentError 只暴露 category，错误码被吃掉；这里补一个旁路通道
    /// 方便看真实 code + message（如 3001 鉴权失败 / 3003 音色未授权）。
    private static let log = Logger(
        subsystem: "com.james.personalagent", category: "DoubaoTTS")

    init(config: ResolvedTTSConfig,
         client: LLMHTTPClient,
         uuid: @escaping @Sendable () -> String = { UUID().uuidString }) {
        self.config = config
        self.client = client
        self.uuid = uuid
    }

    /// 仅形状检查，零网络（契约层约定）。
    func validate() throws {
        guard let scheme = config.hostUrl.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              config.hostUrl.host != nil else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "invalid host_url")
        }
        guard !config.vcn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "missing vcn")
        }
        guard !config.doubaoAppId.isEmpty, !config.doubaoToken.isEmpty else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "missing doubao credentials")
        }
    }

    func synthesize(_ text: String) async throws -> AudioResult {
        try validate()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "empty text")
        }

        let request = try makeRequest(text: trimmed)

        let data: Data
        let response: HTTPURLResponse
        do {
            try Task.checkCancellation()
            (data, response) = try await client.send(request)
            try Task.checkCancellation()
        } catch let error as AgentError {
            throw error
        } catch is CancellationError {
            throw AgentError(category: .cancelled,
                             diagnosticMessage: "request cancelled")
        } catch let urlError as URLError {
            throw DoubaoTTSProvider.mapURLError(urlError)
        } catch {
            throw AgentError(category: .network, isRetriable: true,
                             diagnosticMessage: "transport failure")
        }

        guard (200..<300).contains(response.statusCode) else {
            // 即便 HTTP 非 2xx，豆包通常仍回 JSON 错误体，打出来便于诊断。
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            DoubaoTTSProvider.log.error(
                "HTTP \(response.statusCode, privacy: .public): \(body, privacy: .public)")
            throw DoubaoTTSProvider.mapHTTPStatus(response.statusCode)
        }

        return try DoubaoTTSProvider.parse(data)
    }

    // MARK: - Request

    private func makeRequest(text: String) throws -> URLRequest {
        var request = URLRequest(url: config.hostUrl)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 豆包文档明确要求 "Bearer;<token>" 这种带分号格式；
        // 写成标准 "Bearer <token>" 会被网关识别失败 401。
        request.setValue("Bearer;\(config.doubaoToken)",
                         forHTTPHeaderField: "Authorization")

        // 字段名严格按 V1 文档：音量是 `loudness_ratio` 不是 `volume_ratio`；
        // 音高调节文档明确"暂不支持"，不发该字段（音调滑杆对豆包静默无效）。
        // `app.token` 文档注明是 fake token，可传任意非空串，但仍传真实
        // token 以便服务端日志关联追溯（鉴权只看 Authorization Header）。
        let body: [String: Any] = [
            "app": [
                "appid": config.doubaoAppId,
                "token": config.doubaoToken,
                "cluster": DoubaoTTSProvider.cluster
            ],
            "user": ["uid": "personalagent"],
            "audio": [
                "voice_type": config.vcn,
                "encoding": "mp3",
                "speed_ratio": DoubaoTTSProvider.ratio(from: config.speed),
                "loudness_ratio": DoubaoTTSProvider.ratio(from: config.volume)
            ],
            "request": [
                "reqid": uuid(),
                "text": text,
                "operation": "query"
            ]
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "failed to encode tts body")
        }
        return request
    }

    /// 0–100 → 0.5x–1.5x（中点 50 = 1.0x，无突兀变速）。豆包接受 0.2–3.0，
    /// 我们刻意收窄成 0.5–1.5，避免滑杆轻微滑动就听感剧变。
    private static func ratio(from value: Int) -> Double {
        let clamped = max(0, min(100, value))
        return 0.5 + Double(clamped) / 100.0
    }

    // MARK: - Failure mapping

    private static func mapURLError(_ error: URLError) -> AgentError {
        switch error.code {
        case .cancelled:
            return AgentError(category: .cancelled,
                              diagnosticMessage: "request cancelled")
        case .timedOut:
            return AgentError(category: .timeout, isRetriable: true,
                              diagnosticMessage: "request timed out")
        default:
            return AgentError(category: .network, isRetriable: true,
                              diagnosticMessage: "network failure",
                              providerErrorCode: "URLError_\(error.code.rawValue)")
        }
    }

    private static func mapHTTPStatus(_ status: Int) -> AgentError {
        let retriable = status >= 500
        return AgentError(category: .providerRejected, isRetriable: retriable,
                          diagnosticMessage: "doubao tts http \(status)",
                          providerErrorCode: "HTTP_\(status)")
    }

    /// 豆包成功响应：`{"code":3000,"data":"<base64 mp3>", ...}`；其它 code
    /// 全部视为 provider 拒绝，错误码带回去便于诊断（如 3001 文本过长）。
    private static func parse(_ data: Data) throws -> AudioResult {
        guard let root = (try? JSONSerialization.jsonObject(with: data))
                as? [String: Any] else {
            throw AgentError(category: .providerRejected,
                             diagnosticMessage: "invalid doubao response")
        }
        let code = (root["code"] as? Int) ?? -1
        guard code == 3000 else {
            let msg = (root["message"] as? String) ?? "code \(code)"
            let reqid = (root["reqid"] as? String) ?? "-"
            log.error(
                "rejected code=\(code, privacy: .public) reqid=\(reqid, privacy: .public) msg=\(msg, privacy: .public)")
            throw AgentError(category: .providerRejected,
                             diagnosticMessage: "doubao rejected: \(msg)",
                             providerErrorCode: "DOUBAO_\(code)")
        }
        guard let base64 = root["data"] as? String,
              let audio = Data(base64Encoded: base64),
              !audio.isEmpty else {
            throw AgentError(category: .providerRejected,
                             diagnosticMessage: "missing audio payload")
        }
        return AudioResult(data: audio, format: "mp3", durationMs: nil)
    }
}
