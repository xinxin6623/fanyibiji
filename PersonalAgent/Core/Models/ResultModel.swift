import Foundation

enum ResultContent: Sendable, Equatable {
    case text(String)
    case translation(text: String, sourceLang: String?, targetLang: String?)
    case audio(ref: String, format: String, durationMs: Int?)
    case dictionary(DictionaryEntry)
}

extension ResultContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, sourceLang, targetLang, ref, format, durationMs, entry
    }

    private enum Kind: String, Codable {
        case text, translation, audio, dictionary
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(value):
            try container.encode(Kind.text, forKey: .type)
            try container.encode(value, forKey: .text)
        case let .translation(text, sourceLang, targetLang):
            try container.encode(Kind.translation, forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(sourceLang, forKey: .sourceLang)
            try container.encodeIfPresent(targetLang, forKey: .targetLang)
        case let .audio(ref, format, durationMs):
            try container.encode(Kind.audio, forKey: .type)
            try container.encode(ref, forKey: .ref)
            try container.encode(format, forKey: .format)
            try container.encodeIfPresent(durationMs, forKey: .durationMs)
        case let .dictionary(entry):
            try container.encode(Kind.dictionary, forKey: .type)
            try container.encode(entry, forKey: .entry)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .translation:
            self = .translation(
                text: try container.decode(String.self, forKey: .text),
                sourceLang: try container.decodeIfPresent(String.self, forKey: .sourceLang),
                targetLang: try container.decodeIfPresent(String.self, forKey: .targetLang)
            )
        case .audio:
            self = .audio(
                ref: try container.decode(String.self, forKey: .ref),
                format: try container.decode(String.self, forKey: .format),
                durationMs: try container.decodeIfPresent(Int.self, forKey: .durationMs)
            )
        case .dictionary:
            self = .dictionary(
                try container.decode(DictionaryEntry.self, forKey: .entry)
            )
        }
    }
}

struct ResultModel: Codable, Sendable, Equatable {
    let id: UUID
    let contextId: UUID
    let provider: String
    let content: ResultContent
    let tags: [String]
    let error: AgentError?
    let createdAt: Date
    /// 原始用户输入文本(原文)。results.jsonl 历史只存译文,无原文 →
    /// 笔记原料包「原文→译文」配对需要它。新增字段:旧 jsonl 行无此键,
    /// 解码用 `decodeIfPresent` 容错为 nil(不破坏既有数据)。
    /// 命名 `sourceText`→`source_text`,无首字母缩写,convertSnakeCase
    /// 往返对称,不踩本仓 Codable 缩写坑。
    let sourceText: String?

    init(
        id: UUID = UUID(),
        contextId: UUID,
        provider: String,
        content: ResultContent,
        tags: [String] = [],
        error: AgentError? = nil,
        createdAt: Date = Date(),
        sourceText: String? = nil
    ) {
        self.id = id
        self.contextId = contextId
        self.provider = provider
        self.content = content
        self.tags = tags
        self.error = error
        self.createdAt = createdAt
        self.sourceText = sourceText
    }

    private enum CodingKeys: String, CodingKey {
        case id, contextId, provider, content, tags, error, createdAt, sourceText
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        contextId = try c.decode(UUID.self, forKey: .contextId)
        provider = try c.decode(String.self, forKey: .provider)
        content = try c.decode(ResultContent.self, forKey: .content)
        tags = try c.decode([String].self, forKey: .tags)
        error = try c.decodeIfPresent(AgentError.self, forKey: .error)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        sourceText = try c.decodeIfPresent(String.self, forKey: .sourceText)
    }

    // 自定义 init(from:) 会同时抑制合成的 encode/Equatable,需显式补全。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(contextId, forKey: .contextId)
        try c.encode(provider, forKey: .provider)
        try c.encode(content, forKey: .content)
        try c.encode(tags, forKey: .tags)
        try c.encodeIfPresent(error, forKey: .error)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(sourceText, forKey: .sourceText)
    }
}
