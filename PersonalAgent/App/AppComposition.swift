import Foundation

/// 当配置/密钥缺失时的降级 provider：调用即抛预置 `AgentError`，
/// 让失败态在 UI 可见（避免静默卡死），真实配置 UI 属后续任务。
struct FailingLLMProvider: LLMProvider {
    let id = "unconfigured-llm"
    let error: AgentError
    func validate() throws { throw error }
    func complete(_ context: QueryContext) async throws -> AssistantResult {
        throw error
    }
}

/// 组合根：解析本地配置 + 密钥，组装垂直闭环依赖。
/// 不在仓库放 key；缺 key 时降级而非崩溃。
enum AppComposition {

    /// 默认 provider 配置（OpenAI-compatible）。真实可配置 UI 属后续任务。
    /// 经 James 确认：走 OpenRouter，模型 `baidu/qianfan-ocr-fast`。
    static let defaultConfig = ProviderConfig(
        baseUrl: "https://openrouter.ai/api/v1",
        model: "baidu/qianfan-ocr-fast"
    )
    static let apiKeyRef = "llm.apiKey"

    /// TTS 偏好（发音人/语速/音量/音调）持久化文件，与 results.jsonl
    /// 同目录。UI 改动写这里，启动读回；缺失/损坏回 `TTSConfig()` 默认。
    static func ttsSettingsFileURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("com.james.personalagent", isDirectory: true)
            .appendingPathComponent("tts-config.json")
    }

    /// 按给定 `TTSConfig` 解析三件套密钥并造 provider；按 `engine` 选
    /// 普通 / 超拟人接口（**同一套 Keychain key**）。缺 key/非法配置
    /// → `FailingTTSProvider` 降级（UI 可见，不崩）。供 ViewModel 在
    /// 设置变更时按新 config 重建。
    @Sendable
    static func makeTTSProvider(_ config: TTSConfig) -> TTSProvider {
        let configStore = TTSConfigStore(secrets: KeychainSecretStore())
        do {
            let resolved = try configStore.resolve(config)
            switch resolved.engine {
            case .standard:
                return XunfeiTTSProvider(
                    config: resolved, client: URLSessionTTSWebSocketClient())
            case .superHuman:
                return SuperTTSProvider(
                    config: resolved, client: URLSessionSuperTTSWebSocketClient())
            }
        } catch let error as AgentError {
            return FailingTTSProvider(error: error)
        } catch {
            return FailingTTSProvider(
                error: AgentError(category: .unknown,
                                  diagnosticMessage: "tts composition failed"))
        }
    }

    @MainActor
    static func makeTTSViewModel() -> TTSPlaybackViewModel {
        let store = TTSSettingsStore(fileURL: ttsSettingsFileURL())
        let settings = store.load()
        return TTSPlaybackViewModel(
            settings: settings,
            settingsStore: store,
            makeProvider: makeTTSProvider)
    }

    /// 快捷键配置持久化文件，与 tts-config.json / results.jsonl 同目录。
    /// 设置界面改动写这里，启动读回；缺失/损坏回 `HotkeyConfig()` 默认。
    static func hotkeySettingsFileURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("com.james.personalagent", isDirectory: true)
            .appendingPathComponent("hotkey-config.json")
    }

    /// 系统提示词配置持久化文件，与其它 config 同目录。
    static func promptSettingsFileURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("com.james.personalagent", isDirectory: true)
            .appendingPathComponent("prompt-config.json")
    }

    static func resultsFileURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("com.james.personalagent", isDirectory: true)
            .appendingPathComponent("results.jsonl")
    }

    /// 按当前 Keychain 里的 LLM key 解析造 provider。缺 key/非法
    /// → `FailingLLMProvider` 降级（UI 可见，不崩）。供启动组装
    /// 与"设置里填完 key 后重建"两处共用（单一事实源）。
    static func makeLLMProvider() -> LLMProvider {
        // 系统提示词从持久化读（缺失/损坏回默认，不让 LLM 失约束）。
        let prompt = PromptSettingsStore(
            fileURL: promptSettingsFileURL()).load().systemPrompt
        let configStore = ConfigStore(secrets: KeychainSecretStore())
        do {
            let resolved = try configStore.resolve(
                defaultConfig, apiKeyRef: apiKeyRef)
            return OpenAICompatibleLLMProvider(
                config: resolved,
                client: URLSessionLLMHTTPClient(),
                systemPrompt: prompt)
        } catch let error as AgentError {
            return FailingLLMProvider(error: error)
        } catch {
            return FailingLLMProvider(
                error: AgentError(category: .unknown,
                                  diagnosticMessage: "composition failed"))
        }
    }

    @MainActor
    static func makeViewModel() -> ContentQueryViewModel {
        let store = JSONLResultStore(fileURL: resultsFileURL())
        let provider = makeLLMProvider()
        // T09 免费翻译 provider 作主翻译通道（免 key、零配置；逆向公开
        // 端点隔离在可替换 provider 层，AGENTS 边界）。
        let translate = FreeWebTranslateProvider(
            client: URLSessionTranslateHTTPClient())
        let clipboard = ClipboardTextGrabber(pasteboard: SystemPasteboard())
        return ContentQueryViewModel(
            provider: provider,
            translateProvider: translate,
            clipboard: clipboard,
            store: store)
    }
}
