import Foundation

enum ResultContent: Sendable, Equatable {
    case text(String)
    case translation(text: String, sourceLang: String?, targetLang: String?)
    case audio(ref: String, format: String, durationMs: Int?)
}

extension ResultContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, sourceLang, targetLang, ref, format, durationMs
    }

    private enum Kind: String, Codable {
        case text, translation, audio
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

    init(
        id: UUID = UUID(),
        contextId: UUID,
        provider: String,
        content: ResultContent,
        tags: [String] = [],
        error: AgentError? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.contextId = contextId
        self.provider = provider
        self.content = content
        self.tags = tags
        self.error = error
        self.createdAt = createdAt
    }
}
