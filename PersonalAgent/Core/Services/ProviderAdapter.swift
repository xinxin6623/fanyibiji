import Foundation

protocol ProviderAdapter: Sendable {
    var id: String { get }
    func validate() throws
}

struct AssistantResult: Sendable, Equatable {
    let text: String
    let model: String?
}

struct TranslationResult: Sendable, Equatable {
    let text: String
    let sourceLang: String?
    let targetLang: String?
}

struct AudioResult: Sendable, Equatable {
    let data: Data
    let format: String
    let durationMs: Int?
}

protocol LLMProvider: ProviderAdapter {
    func complete(_ context: QueryContext) async throws -> AssistantResult
}

protocol TranslateProvider: ProviderAdapter {
    func translate(_ context: QueryContext) async throws -> TranslationResult
}

protocol TTSProvider: ProviderAdapter {
    func synthesize(_ text: String) async throws -> AudioResult
}
