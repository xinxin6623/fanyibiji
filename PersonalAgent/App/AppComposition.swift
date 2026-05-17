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
        let configStore = TTSConfigStore(secrets: makeSecretStore())
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

    /// 加密密钥库文件（AES-GCM），与其它 config 同目录。换掉
    /// Keychain：开发期反复 rebuild 不再弹系统密码框（根因是本地
    /// 签名指纹漂移使 Keychain ACL 对不上）。
    static func secretStoreFileURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("com.james.personalagent", isDirectory: true)
            .appendingPathComponent("secrets.enc")
    }

    /// 全 App 统一的密钥库实例工厂（单一事实源，便于将来再切实现）。
    /// 用缓存单例：首次构造时**一次性**从旧 Keychain 迁移历史密钥到
    /// 新文件（换存储后端后旧 key 不会自动出现，否则 LLM/翻译瘫痪），
    /// 之后 3 个调用点共享同一实例，迁移不重复跑、不反复读 Keychain。
    static func makeSecretStore() -> SecretStore { sharedSecretStore }

    private static let sharedSecretStore: SecretStore = {
        let store = FileSecretStore(fileURL: secretStoreFileURL())
        // 旧 Keychain account 名，与 AppController.secretRefs 同源
        // （那边是 UI 展示单一事实源；迁移只需 id，复制 4 个字面量
        // 并加此注释，避免 Composition 反向依赖 Controller）。
        store.migrateFromKeychainIfNeeded(
            keys: ["llm.apiKey", "tts.appId", "tts.apiKey", "tts.apiSecret"],
            legacy: KeychainSecretStore())
        return store
    }()

    /// 语言配置持久化文件，与其它 config 同目录。
    static func languageSettingsFileURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("com.james.personalagent", isDirectory: true)
            .appendingPathComponent("language-config.json")
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

    /// 笔记暂存草稿文件，与其它 config / results.jsonl 同目录但单独成
    /// 文件（notes/note-draft.md）。与翻译历史完全分离，后续 LLM 结构化
    /// 「最终笔记生成」时再回头抓 results.jsonl 原始内容。
    /// 多草稿目录(notes/)。每草稿一个 draft-<id>.md + sidecar,外加
    /// manifest.json。不再用单一 note-draft.md(全新多草稿体系)。
    static func notesDirectoryURL() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("com.james.personalagent", isDirectory: true)
            .appendingPathComponent("notes", isDirectory: true)
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
        let configStore = ConfigStore(secrets: makeSecretStore())
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

    @MainActor
    static func makeNoteDocumentsViewModel() -> NoteDocumentsViewModel {
        NoteDocumentsViewModel(
            store: NoteDraftStore(notesDirectory: notesDirectoryURL()))
    }

    /// 笔记原料包导出需读全量翻译历史(原文→译文配对)。复用 results
    /// 同一文件,只读。
    static func makeResultStoreForExport() -> JSONLResultStore {
        JSONLResultStore(fileURL: resultsFileURL())
    }
}
