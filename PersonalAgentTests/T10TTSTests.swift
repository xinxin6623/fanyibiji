import XCTest
@testable import PersonalAgent

/// T10 讯飞 TTS：鉴权签名 / 首帧编码 / 帧拼接与错误码 / 配置解析 /
/// provider 失败映射。全部零网络（注入桩 + 固定时钟），确定性断言。
final class T10TTSTests: XCTestCase {

    // MARK: - TTSConfig 编码契约

    func testTTSConfigSnakeCaseRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let original = TTSConfig(vcn: "xiaoyan", speed: 60)
        let data = try encoder.encode(original)
        XCTAssertEqual(try decoder.decode(TTSConfig.self, from: data), original)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("host_url"))
    }

    // MARK: - 鉴权签名（固定 date 可复现）

    private let fixedDate = Date(timeIntervalSince1970: 1_564_624_401) // 2019-08-01 01:53:21 GMT

    func testRFC1123DateIsGMT() {
        XCTAssertEqual(XunfeiTTSAuth.rfc1123Date(fixedDate),
                       "Thu, 01 Aug 2019 01:53:21 GMT")
    }

    func testSignedURLHasAuthQueryAndIsDeterministic() throws {
        let host = URL(string: "wss://tts-api.xfyun.cn/v2/tts")!
        let u1 = try XunfeiTTSAuth.signedURL(
            host: host, apiKey: "KEY", apiSecret: "SECRET", date: fixedDate)
        let u2 = try XunfeiTTSAuth.signedURL(
            host: host, apiKey: "KEY", apiSecret: "SECRET", date: fixedDate)
        XCTAssertEqual(u1, u2, "同 date/密钥签名须确定")
        let comps = URLComponents(url: u1, resolvingAgainstBaseURL: false)!
        let names = Set(comps.queryItems!.map(\.name))
        XCTAssertEqual(names, ["authorization", "date", "host"])
        XCTAssertEqual(comps.scheme, "wss")
        XCTAssertEqual(comps.host, "tts-api.xfyun.cn")
        // 不同 secret 必产不同签名
        let u3 = try XunfeiTTSAuth.signedURL(
            host: host, apiKey: "KEY", apiSecret: "OTHER", date: fixedDate)
        XCTAssertNotEqual(u1, u3)
    }

    // MARK: - 首帧编码

    func testRequestFrameShapeAndBase64Text() throws {
        let data = try XunfeiTTSAuth.requestFrame(
            appId: "APP", vcn: "xiaoyan", speed: 50, volume: 50,
            pitch: 50, text: "你好")
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let common = root["common"] as! [String: Any]
        let business = root["business"] as! [String: Any]
        let payload = root["data"] as! [String: Any]
        XCTAssertEqual(common["app_id"] as? String, "APP")
        XCTAssertEqual(business["aue"] as? String, "lame")
        XCTAssertEqual(business["vcn"] as? String, "xiaoyan")
        XCTAssertEqual(payload["status"] as? Int, 2)
        let decoded = Data(base64Encoded: payload["text"] as! String)!
        XCTAssertEqual(String(decoding: decoded, as: UTF8.self), "你好")
    }

    func testRequestFrameRejectsEmptyText() {
        XCTAssertThrowsError(try XunfeiTTSAuth.requestFrame(
            appId: "A", vcn: "v", speed: 0, volume: 0, pitch: 0, text: "  ")) {
            XCTAssertEqual(($0 as? AgentError)?.category, .invalidInput)
        }
    }

    func testRequestFrameRejectsOversizedText() {
        let big = String(repeating: "a", count: 8001)
        XCTAssertThrowsError(try XunfeiTTSAuth.requestFrame(
            appId: "A", vcn: "v", speed: 0, volume: 0, pitch: 0, text: big)) {
            XCTAssertEqual(($0 as? AgentError)?.category, .invalidInput)
        }
    }

    // MARK: - 帧累加器

    private func frame(_ obj: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: obj)
    }

    func testCollectorConcatenatesAudioUntilStatus2() throws {
        var c = TTSFrameCollector()
        let part1 = Data([0x01, 0x02]).base64EncodedString()
        let part2 = Data([0x03]).base64EncodedString()
        try c.ingest(frame(["code": 0, "data": ["audio": part1, "status": 1]]))
        XCTAssertFalse(c.isComplete)
        try c.ingest(frame(["code": 0, "data": ["audio": part2, "status": 2]]))
        XCTAssertTrue(c.isComplete)
        XCTAssertEqual(c.audioData, Data([0x01, 0x02, 0x03]))
    }

    func testCollectorMapsErrorCodeToProviderRejected() {
        var c = TTSFrameCollector()
        XCTAssertThrowsError(try c.ingest(frame(["code": 10005,
                                                 "message": "auth failed"]))) {
            let e = $0 as? AgentError
            XCTAssertEqual(e?.category, .providerRejected)
            XCTAssertEqual(e?.providerErrorCode, "XF_10005")
            XCTAssertEqual(e?.isRetriable, false)
        }
    }

    func testCollectorFlowControlCodeIsRetriable() {
        var c = TTSFrameCollector()
        XCTAssertThrowsError(try c.ingest(frame(["code": 11201]))) {
            XCTAssertEqual(($0 as? AgentError)?.isRetriable, true)
        }
    }

    // MARK: - 配置解析

    func testConfigStoreResolvesWithThreeSecrets() throws {
        let store = TTSConfigStore(secrets: InMemorySecretStore([
            "tts.appId": "APP", "tts.apiKey": "KEY", "tts.apiSecret": "SEC"]))
        let resolved = try store.resolve(TTSConfig())
        XCTAssertEqual(resolved.appId, "APP")
        XCTAssertEqual(resolved.apiKey, "KEY")
        XCTAssertEqual(resolved.apiSecret, "SEC")
    }

    func testConfigStoreMissingSecretIsInvalidInput() {
        let store = TTSConfigStore(secrets: InMemorySecretStore([
            "tts.appId": "APP"])) // 缺 apiKey/apiSecret
        XCTAssertThrowsError(try store.resolve(TTSConfig())) {
            XCTAssertEqual(($0 as? AgentError)?.category, .invalidInput)
        }
    }

    func testConfigStoreRejectsOutOfRangeSpeed() {
        let store = TTSConfigStore(secrets: InMemorySecretStore([
            "tts.appId": "A", "tts.apiKey": "K", "tts.apiSecret": "S"]))
        XCTAssertThrowsError(try store.resolve(TTSConfig(speed: 200))) {
            XCTAssertEqual(($0 as? AgentError)?.category, .invalidInput)
        }
    }

    // MARK: - Provider 失败映射

    private func resolved(engine: TTSEngine = .standard) -> ResolvedTTSConfig {
        ResolvedTTSConfig(
            engine: engine,
            hostUrl: URL(string: engine.defaultHost)!,
            vcn: engine.defaultVcn, speed: 50, volume: 50, pitch: 50,
            oralLevel: .mid, timeoutSeconds: 5,
            appId: "A", apiKey: "K", apiSecret: "S")
    }

    func testProviderReturnsMP3OnSuccess() async throws {
        let client = StubTTSClient(.success(Data([0x49, 0x44, 0x33]))) // "ID3"
        let provider = XunfeiTTSProvider(
            config: resolved(), client: client, now: { Date() })
        let result = try await provider.synthesize("你好")
        XCTAssertEqual(result.format, "mp3")
        XCTAssertEqual(result.data, Data([0x49, 0x44, 0x33]))
    }

    func testProviderPropagatesAgentErrorFromClient() async {
        let err = AgentError(category: .providerRejected,
                             diagnosticMessage: "rej", providerErrorCode: "XF_10005")
        let provider = XunfeiTTSProvider(
            config: resolved(), client: StubTTSClient(.failure(err)),
            now: { Date() })
        do {
            _ = try await provider.synthesize("你好")
            XCTFail("应抛错")
        } catch let e as AgentError {
            XCTAssertEqual(e.category, .providerRejected)
            XCTAssertEqual(e.providerErrorCode, "XF_10005")
        } catch { XCTFail("错误类型不对") }
    }

    func testProviderEmptyAudioIsProviderRejected() async {
        let provider = XunfeiTTSProvider(
            config: resolved(), client: StubTTSClient(.success(Data())),
            now: { Date() })
        do {
            _ = try await provider.synthesize("你好")
            XCTFail("应抛错")
        } catch let e as AgentError {
            XCTAssertEqual(e.category, .providerRejected)
        } catch { XCTFail("错误类型不对") }
    }

    func testFailingTTSProviderAlwaysThrows() async {
        let err = AgentError(category: .invalidInput, diagnosticMessage: "no key")
        let provider = FailingTTSProvider(error: err)
        XCTAssertThrowsError(try provider.validate())
        do {
            _ = try await provider.synthesize("x")
            XCTFail("应抛错")
        } catch let e as AgentError {
            XCTAssertEqual(e.category, .invalidInput)
        } catch { XCTFail("错误类型不对") }
    }

    // MARK: - 设置持久化（TTSSettingsStore）

    private func tempSettingsURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("tts-config.json")
    }

    func testSettingsRoundTrip() throws {
        let store = TTSSettingsStore(fileURL: tempSettingsURL())
        let cfg = TTSConfig(vcn: "aisjiuxu", speed: 70, volume: 80, pitch: 30)
        try store.save(cfg)
        XCTAssertEqual(store.load(), cfg)
    }

    func testSettingsMissingFileReturnsDefault() {
        let store = TTSSettingsStore(fileURL: tempSettingsURL())
        XCTAssertEqual(store.load(), TTSConfig())
    }

    func testSettingsCorruptFileReturnsDefault() throws {
        let url = tempSettingsURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        XCTAssertEqual(TTSSettingsStore(fileURL: url).load(), TTSConfig())
    }

    func testSettingsClampsOutOfRangeOnLoad() throws {
        let url = tempSettingsURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 手写越界 JSON（绕过 save 的 sanitize），验证 load 也夹回。
        try Data(#"{"host_url":"wss://x/y","vcn":"v","speed":999,"volume":-5,"pitch":50,"timeout_seconds":30}"#.utf8)
            .write(to: url)
        let loaded = TTSSettingsStore(fileURL: url).load()
        XCTAssertEqual(loaded.speed, 100)
        XCTAssertEqual(loaded.volume, 0)
    }

    @MainActor
    func testViewModelChangeRebuildsProviderAndPersists() async throws {
        let url = tempSettingsURL()
        let store = TTSSettingsStore(fileURL: url)
        var builtConfigs: [TTSConfig] = []
        let vm = TTSPlaybackViewModel(
            settings: TTSConfig(),
            settingsStore: store,
            makeProvider: { cfg in
                builtConfigs.append(cfg)
                return FailingTTSProvider(
                    error: AgentError(category: .invalidInput))
            })
        XCTAssertEqual(builtConfigs.count, 1) // 初始一次
        vm.vcn = "aisjiuxu"
        vm.speed = 88
        XCTAssertEqual(builtConfigs.count, 3) // 两次改动各重建一次
        XCTAssertEqual(builtConfigs.last?.vcn, "aisjiuxu")
        XCTAssertEqual(builtConfigs.last?.speed, 88)
        // debounce 0.4s 落盘：轮询至生效（最长 3s），避免固定 sleep 在
        // 并行负载下与 debounce 抢跑导致偶发失败（快路径仍很快返回）。
        try await waitUntil(timeout: 3) {
            store.load().vcn == "aisjiuxu" && store.load().speed == 88
        }
        XCTAssertEqual(store.load().vcn, "aisjiuxu")
        XCTAssertEqual(store.load().speed, 88)
    }

    /// 轮询直到 `condition` 为真或超时（每 50ms 查一次）。比固定
    /// `Task.sleep` 稳健：负载高时多等，正常时几乎立刻返回。
    private func waitUntil(timeout: TimeInterval,
                           _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                XCTFail("waitUntil timed out after \(timeout)s")
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - 引擎切换 / 超拟人接口

    func testDefaultEngineIsSuperHuman() {
        let c = TTSConfig()
        XCTAssertEqual(c.engine, .superHuman)
        XCTAssertEqual(c.vcn, "x5_lingxiaoxuan_flow")
        XCTAssertTrue(c.hostUrl.contains("xf-yun.com"))
    }

    func testOldConfigWithoutEngineDecodesToSuperDefault() throws {
        // 模拟 T10 旧版本写的配置（无 engine/oral_level）。
        let legacy = #"{"host_url":"wss://tts-api.xfyun.cn/v2/tts","vcn":"xiaoyan","speed":55,"volume":50,"pitch":50,"timeout_seconds":30}"#
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        let c = try dec.decode(TTSConfig.self, from: Data(legacy.utf8))
        XCTAssertEqual(c.engine, .superHuman)   // 缺字段回默认
        XCTAssertEqual(c.speed, 55)             // 旧字段保留
        XCTAssertEqual(c.oralLevel, .mid)
    }

    func testConfigStoreResolveCarriesEngineAndOral() throws {
        let store = TTSConfigStore(secrets: InMemorySecretStore([
            "tts.appId": "A", "tts.apiKey": "K", "tts.apiSecret": "S"]))
        let r = try store.resolve(TTSConfig(engine: .superHuman,
                                            oralLevel: .high))
        XCTAssertEqual(r.engine, .superHuman)
        XCTAssertEqual(r.oralLevel, .high)
        XCTAssertTrue(r.hostUrl.absoluteString.contains("xf-yun.com"))
    }

    func testSuperRequestFrameShape() throws {
        let data = try SuperTTSRequest.frame(
            appId: "APP", vcn: "x5_lingxiaoxuan_flow",
            speed: 50, volume: 50, pitch: 50,
            oralLevel: .high, text: "你好")
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let header = root["header"] as! [String: Any]
        let param = root["parameter"] as! [String: Any]
        let oral = param["oral"] as! [String: Any]
        let tts = param["tts"] as! [String: Any]
        let audio = tts["audio"] as! [String: Any]
        let payloadText = (root["payload"] as! [String: Any])["text"] as! [String: Any]
        XCTAssertEqual(header["app_id"] as? String, "APP")
        XCTAssertEqual(header["status"] as? Int, 2)
        XCTAssertEqual(oral["oral_level"] as? String, "high")
        XCTAssertEqual(tts["vcn"] as? String, "x5_lingxiaoxuan_flow")
        XCTAssertEqual(audio["encoding"] as? String, "lame")
        XCTAssertEqual(audio["sample_rate"] as? Int, 24000)
        let decoded = Data(base64Encoded: payloadText["text"] as! String)!
        XCTAssertEqual(String(decoding: decoded, as: UTF8.self), "你好")
    }

    func testSuperRequestFrameRejectsEmptyText() {
        XCTAssertThrowsError(try SuperTTSRequest.frame(
            appId: "A", vcn: "v", speed: 0, volume: 0, pitch: 0,
            oralLevel: .mid, text: "  ")) {
            XCTAssertEqual(($0 as? AgentError)?.category, .invalidInput)
        }
    }

    func testSuperCollectorConcatenatesUntilStatus2() throws {
        var c = SuperTTSFrameCollector()
        func frame(_ o: [String: Any]) -> Data {
            try! JSONSerialization.data(withJSONObject: o)
        }
        let p1 = Data([0xAA]).base64EncodedString()
        let p2 = Data([0xBB]).base64EncodedString()
        try c.ingest(frame(["header": ["code": 0, "status": 1],
                            "payload": ["audio": ["audio": p1, "status": 1]]]))
        XCTAssertFalse(c.isComplete)
        try c.ingest(frame(["header": ["code": 0, "status": 2],
                            "payload": ["audio": ["audio": p2, "status": 2]]]))
        XCTAssertTrue(c.isComplete)
        XCTAssertEqual(c.audioData, Data([0xAA, 0xBB]))
    }

    func testSuperCollectorMapsErrorCode() {
        var c = SuperTTSFrameCollector()
        let f = try! JSONSerialization.data(withJSONObject:
            ["header": ["code": 10005, "message": "auth failed"]])
        XCTAssertThrowsError(try c.ingest(f)) {
            let e = $0 as? AgentError
            XCTAssertEqual(e?.category, .providerRejected)
            XCTAssertEqual(e?.providerErrorCode, "XF_10005")
        }
    }

    func testSuperProviderReturnsMP3() async throws {
        let provider = SuperTTSProvider(
            config: resolved(engine: .superHuman),
            client: StubSuperTTSClient(.success(Data([0x49, 0x44, 0x33]))),
            now: { Date() })
        let r = try await provider.synthesize("你好")
        XCTAssertEqual(r.format, "mp3")
        XCTAssertEqual(r.data, Data([0x49, 0x44, 0x33]))
    }

    @MainActor
    func testViewModelEngineSwitchResetsVcnAndRebuilds() async throws {
        var built: [TTSConfig] = []
        let vm = TTSPlaybackViewModel(
            settings: TTSConfig(engine: .standard, vcn: "xiaoyan"),
            settingsStore: TTSSettingsStore(fileURL: tempSettingsURL()),
            makeProvider: { c in built.append(c)
                return FailingTTSProvider(error: AgentError(category: .invalidInput)) })
        XCTAssertEqual(built.count, 1)
        vm.engine = .superHuman
        // engine.didSet → vcn 重置为超拟人默认 → vcn.didSet 触发一次重建
        XCTAssertEqual(vm.vcn, "x5_lingxiaoxuan_flow")
        XCTAssertEqual(built.last?.engine, .superHuman)
        XCTAssertTrue(built.last!.hostUrl.contains("xf-yun.com"))
    }
}

/// 超拟人桩：一次性返回预置结果或错误，不触网。
private struct StubSuperTTSClient: SuperTTSWebSocketClient {
    let outcome: Result<Data, AgentError>
    init(_ outcome: Result<Data, AgentError>) { self.outcome = outcome }
    func synthesize(url: URL, requestFrame: Data,
                    timeoutSeconds: Double) async throws -> Data {
        switch outcome {
        case let .success(d): return d
        case let .failure(e): throw e
        }
    }
}

/// 单测桩：一次性返回预置结果或错误，不触网。
private struct StubTTSClient: TTSWebSocketClient {
    let outcome: Result<Data, AgentError>
    init(_ outcome: Result<Data, AgentError>) { self.outcome = outcome }
    func synthesize(url: URL, requestFrame: Data,
                    timeoutSeconds: Double) async throws -> Data {
        switch outcome {
        case let .success(d): return d
        case let .failure(e): throw e
        }
    }
}
