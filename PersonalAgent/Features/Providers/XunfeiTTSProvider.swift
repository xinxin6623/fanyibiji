import Foundation

/// 讯飞在线语音合成 provider（WebSocket，攒整段，输出 MP3）。
///
/// 消费 `TTSConfigStore.resolve` 产出的 `ResolvedTTSConfig`（不自读
/// Keychain）。`validate()` 仅形状检查、零网络（契约层约定）。所有
/// 失败统一映射 `AgentError`，UI 只按 `category` 分支，不暴露讯飞
/// 私有错误码（错误码进 `providerErrorCode` 仅作诊断）。
struct XunfeiTTSProvider: TTSProvider {
    let id = "xunfei-tts"

    private let config: ResolvedTTSConfig
    private let client: TTSWebSocketClient
    /// 注入时钟，便于单测对鉴权 date 做确定性断言。
    private let now: @Sendable () -> Date

    init(config: ResolvedTTSConfig,
         client: TTSWebSocketClient,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.client = client
        self.now = now
    }

    /// 仅形状检查，零网络（契约层约定）。
    func validate() throws {
        guard config.hostUrl.scheme?.hasPrefix("ws") == true,
              config.hostUrl.host != nil else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "invalid host_url")
        }
        guard !config.vcn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "missing vcn")
        }
        guard !config.appId.isEmpty,
              !config.apiKey.isEmpty,
              !config.apiSecret.isEmpty else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "missing tts credentials")
        }
    }

    func synthesize(_ text: String) async throws -> AudioResult {
        try validate()

        let signedURL = try XunfeiTTSAuth.signedURL(
            host: config.hostUrl,
            apiKey: config.apiKey,
            apiSecret: config.apiSecret,
            date: now())

        let frame = try XunfeiTTSAuth.requestFrame(
            appId: config.appId,
            vcn: config.vcn,
            speed: config.speed,
            volume: config.volume,
            pitch: config.pitch,
            text: text)

        let audio: Data
        do {
            try Task.checkCancellation()
            audio = try await client.synthesize(
                url: signedURL,
                requestFrame: frame,
                timeoutSeconds: config.timeoutSeconds)
            try Task.checkCancellation()
        } catch let error as AgentError {
            throw error
        } catch is CancellationError {
            throw AgentError(category: .cancelled,
                             diagnosticMessage: "tts cancelled")
        } catch let urlError as URLError {
            throw XunfeiTTSProvider.mapURLError(urlError)
        } catch {
            throw AgentError(category: .network,
                             isRetriable: true,
                             diagnosticMessage: "tts transport failure")
        }

        guard !audio.isEmpty else {
            throw AgentError(category: .providerRejected,
                             diagnosticMessage: "tts returned empty audio")
        }
        return AudioResult(data: audio, format: "mp3", durationMs: nil)
    }

    // MARK: - Failure mapping

    private static func mapURLError(_ error: URLError) -> AgentError {
        switch error.code {
        case .cancelled:
            return AgentError(category: .cancelled,
                              diagnosticMessage: "tts cancelled")
        case .timedOut:
            return AgentError(category: .timeout, isRetriable: true,
                              diagnosticMessage: "tts timed out")
        default:
            return AgentError(category: .network, isRetriable: true,
                              diagnosticMessage: "tts network failure",
                              providerErrorCode: "URLError_\(error.code.rawValue)")
        }
    }
}

/// 讯飞**超拟人**语音合成 provider（WebSocket，攒整段，输出 MP3）。
///
/// 与 `XunfeiTTSProvider` 同结构、同 `AgentError` 映射、同零网络
/// `validate()`，仅走超拟人接口（不同 host/path、header/parameter/
/// payload 结构、口语化参数）。鉴权复用 `XunfeiTTSAuth.signedURL`。
struct SuperTTSProvider: TTSProvider {
    let id = "xunfei-super-tts"

    private let config: ResolvedTTSConfig
    private let client: SuperTTSWebSocketClient
    private let now: @Sendable () -> Date

    init(config: ResolvedTTSConfig,
         client: SuperTTSWebSocketClient,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.client = client
        self.now = now
    }

    func validate() throws {
        guard config.hostUrl.scheme?.hasPrefix("ws") == true,
              config.hostUrl.host != nil else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "invalid host_url")
        }
        guard !config.vcn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "missing vcn")
        }
        guard !config.appId.isEmpty,
              !config.apiKey.isEmpty,
              !config.apiSecret.isEmpty else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "missing tts credentials")
        }
    }

    func synthesize(_ text: String) async throws -> AudioResult {
        try validate()

        let signedURL = try XunfeiTTSAuth.signedURL(
            host: config.hostUrl,
            apiKey: config.apiKey,
            apiSecret: config.apiSecret,
            date: now())

        let frame = try SuperTTSRequest.frame(
            appId: config.appId,
            vcn: config.vcn,
            speed: config.speed,
            volume: config.volume,
            pitch: config.pitch,
            oralLevel: config.oralLevel,
            text: text)

        let audio: Data
        do {
            try Task.checkCancellation()
            audio = try await client.synthesize(
                url: signedURL,
                requestFrame: frame,
                timeoutSeconds: config.timeoutSeconds)
            try Task.checkCancellation()
        } catch let error as AgentError {
            throw error
        } catch is CancellationError {
            throw AgentError(category: .cancelled,
                             diagnosticMessage: "super tts cancelled")
        } catch let urlError as URLError {
            throw SuperTTSProvider.mapURLError(urlError)
        } catch {
            throw AgentError(category: .network,
                             isRetriable: true,
                             diagnosticMessage: "super tts transport failure")
        }

        guard !audio.isEmpty else {
            throw AgentError(category: .providerRejected,
                             diagnosticMessage: "super tts returned empty audio")
        }
        return AudioResult(data: audio, format: "mp3", durationMs: nil)
    }

    private static func mapURLError(_ error: URLError) -> AgentError {
        switch error.code {
        case .cancelled:
            return AgentError(category: .cancelled,
                              diagnosticMessage: "super tts cancelled")
        case .timedOut:
            return AgentError(category: .timeout, isRetriable: true,
                              diagnosticMessage: "super tts timed out")
        default:
            return AgentError(category: .network, isRetriable: true,
                              diagnosticMessage: "super tts network failure",
                              providerErrorCode: "URLError_\(error.code.rawValue)")
        }
    }
}

/// 当配置/密钥缺失时的降级 provider：调用即抛预置 `AgentError`，
/// 让失败态在 UI 可见（避免静默卡死）。与 `FailingLLMProvider` 同策略。
struct FailingTTSProvider: TTSProvider {
    let id = "unconfigured-tts"
    let error: AgentError
    func validate() throws { throw error }
    func synthesize(_ text: String) async throws -> AudioResult {
        throw error
    }
}
