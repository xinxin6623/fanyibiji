import Foundation

/// 免费 Web 翻译 provider（逆向公开端点）。
///
/// AGENTS 边界：逆向 Web API **隔离在可替换 provider 层**，不得成为核心
/// 业务依赖——故只实现 `TranslateProvider`，错误统一 `AgentError`，
/// 失败不波及 LLM 主路径（两者无共享状态、各自 HTTPClient）。响应格式
/// 是非官方契约，集中在 `parse` 一处，便于整体替换。
struct FreeWebTranslateProvider: TranslateProvider {
    let id = "free-web-translate"

    private let client: TranslateHTTPClient
    private let endpoint: URL
    private let defaultTargetLang: String

    init(client: TranslateHTTPClient,
         endpoint: URL = URL(string: "https://translate.googleapis.com/translate_a/single")!,
         defaultTargetLang: String = "zh") {
        self.client = client
        self.endpoint = endpoint
        self.defaultTargetLang = defaultTargetLang
    }

    func validate() throws {
        guard endpoint.scheme?.hasPrefix("http") == true, endpoint.host != nil else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "invalid translate endpoint")
        }
    }

    func translate(_ context: QueryContext) async throws -> TranslationResult {
        try validate()
        let text = context.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "empty input text")
        }
        let target = context.languageHints.first?.trimmingCharacters(
            in: .whitespacesAndNewlines).nonEmpty ?? defaultTargetLang

        let request = try makeRequest(text: text, target: target)

        let data: Data
        let response: HTTPURLResponse
        do {
            try Task.checkCancellation()
            (data, response) = try await client.send(request)
            try Task.checkCancellation()
        } catch let error as AgentError {
            throw error
        } catch is CancellationError {
            throw AgentError(category: .cancelled, diagnosticMessage: "translate cancelled")
        } catch let urlError as URLError {
            throw FreeWebTranslateProvider.mapURLError(urlError)
        } catch {
            throw AgentError(category: .network, isRetriable: true,
                             diagnosticMessage: "transport failure")
        }

        guard (200..<300).contains(response.statusCode) else {
            throw AgentError(category: .providerRejected,
                             isRetriable: response.statusCode >= 500,
                             diagnosticMessage: "translate http \(response.statusCode)",
                             providerErrorCode: "HTTP_\(response.statusCode)")
        }

        return try FreeWebTranslateProvider.parse(data, target: target)
    }

    // MARK: - Request

    private func makeRequest(text: String, target: String) throws -> URLRequest {
        guard var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "invalid translate endpoint")
        }
        comps.queryItems = [
            .init(name: "client", value: "gtx"),
            .init(name: "sl", value: "auto"),
            .init(name: "tl", value: target),
            .init(name: "dt", value: "t"),
            .init(name: "q", value: text)
        ]
        guard let url = comps.url else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "failed to build translate url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        return request
    }

    // MARK: - Failure / parse

    private static func mapURLError(_ error: URLError) -> AgentError {
        switch error.code {
        case .cancelled:
            return AgentError(category: .cancelled, diagnosticMessage: "translate cancelled")
        case .timedOut:
            return AgentError(category: .timeout, isRetriable: true,
                              diagnosticMessage: "translate timed out")
        default:
            return AgentError(category: .network, isRetriable: true,
                              diagnosticMessage: "network failure",
                              providerErrorCode: "URLError_\(error.code.rawValue)")
        }
    }

    /// 解析非官方响应：`[[["译文","原文",...], ...], ..., "源语言"]`。
    /// 形状不符一律 `.providerRejected`，不向上抛 provider 私有细节。
    private static func parse(_ data: Data, target: String) throws -> TranslationResult {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [Any],
              let segments = root.first as? [Any] else {
            throw AgentError(category: .providerRejected,
                             diagnosticMessage: "invalid translate response")
        }
        var translated = ""
        for seg in segments {
            if let pair = seg as? [Any], let piece = pair.first as? String {
                translated += piece
            }
        }
        guard !translated.isEmpty else {
            throw AgentError(category: .providerRejected,
                             diagnosticMessage: "empty translation")
        }
        let detected = (root.count > 2 ? root[2] as? String : nil)
        return TranslationResult(text: translated,
                                 sourceLang: detected,
                                 targetLang: target)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
