import CryptoKit
import Foundation

/// 有道词典 Web V4 接口（逆向公开端点）→ `DictionaryEntry`。
///
/// AGENTS 边界：与 `FreeWebTranslateProvider` 同性质——逆向 Web API
/// **隔离在可替换 provider 层**，不得成为核心业务依赖；失败统一
/// `AgentError`，不波及翻译/LLM 主路径。响应字段宽松解码，未知键
/// 全部忽略——有道历史上换过签名(V2→V4)，模型脆耦合是雷区。
///
/// 仅支持 en/ja/ko/fr ↔ zh-CHS（接口本身限制）。语言不支持时直接
/// `.invalidInput`，UI 据此显示"换用翻译"按钮。
struct YoudaoDictProvider: DictionaryProvider {
    let id = "youdao-dict-web"

    private let client: TranslateHTTPClient
    private let endpoint: URL
    /// 网页端硬编码常量(2026-05 抓包仍有效)。换签名时改这里。
    private static let signKey = "Mk6hqtUp33DGGtoS63tTJbMUYjRrG1Lu"
    private static let cookie = "OUTFOX_SEARCH_USER_ID=1796239350@10.110.96.157;"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
    private static let supportedForeignLangs: Set<String> = ["eng", "jap", "ko", "fr"]

    init(client: TranslateHTTPClient,
         endpoint: URL = URL(string: "https://dict.youdao.com/jsonapi_s?doctype=json&jsonversion=4")!) {
        self.client = client
        self.endpoint = endpoint
    }

    func validate() throws {
        guard endpoint.scheme?.hasPrefix("http") == true, endpoint.host != nil else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "invalid dict endpoint")
        }
    }

    func lookup(_ context: QueryContext) async throws -> DictionaryEntry {
        try validate()
        let text = context.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw AgentError(category: .invalidInput,
                             diagnosticMessage: "empty lookup text")
        }
        let foreign = Self.detectForeignLang(text)
        guard let foreign else {
            throw AgentError(category: .invalidInput,
                             providerErrorCode: "UNSUPPORTED_LANG")
        }

        let request = try makeRequest(text: text, foreign: foreign)
        let data: Data
        let response: HTTPURLResponse
        do {
            try Task.checkCancellation()
            (data, response) = try await client.send(request)
            try Task.checkCancellation()
        } catch let error as AgentError {
            throw error
        } catch is CancellationError {
            throw AgentError(category: .cancelled, diagnosticMessage: "dict cancelled")
        } catch let urlError as URLError {
            throw Self.mapURLError(urlError)
        } catch {
            throw AgentError(category: .network, isRetriable: true,
                             diagnosticMessage: "dict transport failure")
        }

        guard (200..<300).contains(response.statusCode) else {
            throw AgentError(category: .providerRejected,
                             isRetriable: response.statusCode >= 500,
                             diagnosticMessage: "dict http \(response.statusCode)",
                             providerErrorCode: "HTTP_\(response.statusCode)")
        }
        return try Self.parse(data, headword: text, source: id)
    }

    // MARK: - Request

    /// 语言粗判：含 ASCII 字母且无 CJK → 英文；含 CJK → 中文(→en)。
    /// 日韩法暂不区分，统一回退 eng；用户场景以英文为主，够用。
    static func detectForeignLang(_ text: String) -> String? {
        let scalars = text.unicodeScalars
        var hasLatin = false
        var hasCJK = false
        for s in scalars {
            switch s.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF: hasCJK = true
            case 0x41...0x5A, 0x61...0x7A: hasLatin = true
            default: break
            }
        }
        if hasCJK { return "eng" } // 中→英查词
        if hasLatin { return "eng" }
        return nil
    }

    private func makeRequest(text: String, foreign: String) throws -> URLRequest {
        let ww = "\(text)webdict"
        let time = String(ww.count % 10)
        let salt = Self.md5Hex(ww)
        let sign = Self.md5Hex("web\(text)\(time)\(Self.signKey)\(salt)")

        // 表单 body：与 Easydict V4 一致(POST + application/x-www-form-urlencoded)。
        let params: [(String, String)] = [
            ("q", text),
            ("le", foreign),
            ("client", "web"),
            ("t", time),
            ("sign", sign),
            ("keyfrom", "webdict"),
        ]
        let body = params.map { k, v in
            "\(Self.formEncode(k))=\(Self.formEncode(v))"
        }.joined(separator: "&")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.httpBody = body.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8",
                         forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://fanyi.youdao.com", forHTTPHeaderField: "Referer")
        request.setValue(Self.cookie, forHTTPHeaderField: "Cookie")
        return request
    }

    private static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private static func md5Hex(_ s: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Failure

    private static func mapURLError(_ error: URLError) -> AgentError {
        switch error.code {
        case .cancelled:
            return AgentError(category: .cancelled, diagnosticMessage: "dict cancelled")
        case .timedOut:
            return AgentError(category: .timeout, isRetriable: true,
                              diagnosticMessage: "dict timed out")
        default:
            return AgentError(category: .network, isRetriable: true,
                              diagnosticMessage: "dict network failure",
                              providerErrorCode: "URLError_\(error.code.rawValue)")
        }
    }

    // MARK: - Parse

    /// 宽松解析：未知字段全忽略；ec(英→中)/ce(中→英) 至少一个有内容,
    /// 否则视为词库无该词 → `.providerRejected`(UI 提示+建议改翻译)。
    static func parse(_ data: Data, headword: String, source: String) throws -> DictionaryEntry {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw AgentError(category: .providerRejected,
                             diagnosticMessage: "dict invalid json")
        }
        if let ec = root["ec"] as? [String: Any] {
            if let entry = parseEC(ec, headword: headword, source: source) {
                return entry
            }
        }
        if let ce = root["ce"] as? [String: Any] {
            if let entry = parseCE(ce, headword: headword, source: source) {
                return entry
            }
        }
        // 最后兜底：fanyi(直接翻译)有内容时也算成功(无音标/词性)。
        if let fanyi = root["fanyi"] as? [String: Any],
           let tran = fanyi["tran"] as? String, !tran.isEmpty {
            return DictionaryEntry(
                headword: headword, summary: tran,
                usIPA: nil, ukIPA: nil,
                usAudioURL: nil, ukAudioURL: nil, audioURL: nil,
                senses: [], forms: [], examTags: [], source: source)
        }
        throw AgentError(category: .providerRejected,
                         diagnosticMessage: "dict empty",
                         providerErrorCode: "NO_ENTRY")
    }

    private static func parseEC(_ ec: [String: Any], headword: String, source: String) -> DictionaryEntry? {
        guard let word = ec["word"] as? [String: Any] else { return nil }
        let usIPA = (word["usphone"] as? String).flatMap(nonEmpty)
        let ukIPA = (word["ukphone"] as? String).flatMap(nonEmpty)
        let usAudio = (word["usspeech"] as? String).flatMap(nonEmpty).map(audioURL)
        let ukAudio = (word["ukspeech"] as? String).flatMap(nonEmpty).map(audioURL)
        let speech = (word["speech"] as? String).flatMap(nonEmpty).map(audioURL)

        var senses: [DictionaryEntry.Sense] = []
        if let trs = word["trs"] as? [[String: Any]] {
            for tr in trs {
                let pos = (tr["pos"] as? String).flatMap(nonEmpty)
                let tran = (tr["tran"] as? String).flatMap(nonEmpty)
                if let tran = tran {
                    senses.append(.init(partOfSpeech: pos, gloss: tran))
                }
            }
        }
        let forms = parseForms(word["wfs"])
        let exam = (ec["examType"] as? [String]) ?? []

        let summary = senses.first?.gloss
        if senses.isEmpty && summary == nil && usIPA == nil && ukIPA == nil { return nil }
        return DictionaryEntry(
            headword: headword, summary: summary,
            usIPA: usIPA, ukIPA: ukIPA,
            usAudioURL: usAudio, ukAudioURL: ukAudio,
            audioURL: (usAudio == nil && ukAudio == nil) ? speech : nil,
            senses: senses, forms: forms, examTags: exam, source: source)
    }

    private static func parseCE(_ ce: [String: Any], headword: String, source: String) -> DictionaryEntry? {
        guard let word = ce["word"] as? [String: Any] else { return nil }
        let phone = (word["phone"] as? String).flatMap(nonEmpty)
        let speech = (word["speech"] as? String).flatMap(nonEmpty).map(audioURL)

        var senses: [DictionaryEntry.Sense] = []
        if let trs = word["trs"] as? [[String: Any]] {
            for tr in trs {
                let pos = (tr["pos"] as? String).flatMap(nonEmpty)
                // CE 分支 tran 可能是字符串,也可能嵌在 #text/text 里。
                let tran = (tr["tran"] as? String).flatMap(nonEmpty)
                    ?? (tr["text"] as? String).flatMap(nonEmpty)
                if let tran = tran {
                    senses.append(.init(partOfSpeech: pos, gloss: tran))
                }
            }
        }
        let summary = senses.first?.gloss
        if senses.isEmpty && summary == nil && phone == nil { return nil }
        return DictionaryEntry(
            headword: headword, summary: summary,
            usIPA: nil, ukIPA: nil,
            usAudioURL: nil, ukAudioURL: nil,
            audioURL: speech,
            senses: senses, forms: [],
            examTags: [],
            source: source).withChinesePhone(phone)
    }

    private static func parseForms(_ raw: Any?) -> [DictionaryEntry.Form] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        var forms: [DictionaryEntry.Form] = []
        for el in arr {
            guard let wf = el["wf"] as? [String: Any],
                  let name = (wf["name"] as? String).flatMap(nonEmpty),
                  let value = (wf["value"] as? String).flatMap(nonEmpty)
            else { continue }
            // 有道用「或」分多形,拆开;同时去重保序。
            let words = value.components(separatedBy: "或")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            forms.append(.init(name: name, words: words))
        }
        return forms
    }

    private static func audioURL(_ speech: String) -> String {
        let encoded = speech.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? speech
        return "https://dict.youdao.com/dictvoice?audio=\(encoded)"
    }

    private static func nonEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

private extension DictionaryEntry {
    /// 中→英分支把中文拼音塞回 usIPA 字段(语义上偷一下,UI 卡片
    /// 渲染拼音 chip 走同一通道)。仅在 phone 非 nil 时改写,其它
    /// 字段保持。
    func withChinesePhone(_ phone: String?) -> DictionaryEntry {
        guard let phone else { return self }
        return DictionaryEntry(
            headword: headword, summary: summary,
            usIPA: phone, ukIPA: nil,
            usAudioURL: usAudioURL, ukAudioURL: ukAudioURL, audioURL: audioURL,
            senses: senses, forms: forms,
            examTags: examTags, source: source)
    }
}
