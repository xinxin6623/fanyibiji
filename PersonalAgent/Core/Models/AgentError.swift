import Foundation

struct AgentError: Error, Codable, Sendable, Equatable {
    enum Category: String, Codable, Sendable {
        case permission
        case network
        case timeout
        case cancelled
        case invalidInput
        case persistence
        case providerRejected
        case unknown
    }

    let category: Category
    let isRetriable: Bool
    let diagnosticMessage: String?
    let providerErrorCode: String?

    init(
        category: Category,
        isRetriable: Bool = false,
        diagnosticMessage: String? = nil,
        providerErrorCode: String? = nil
    ) {
        self.category = category
        self.isRetriable = isRetriable
        self.diagnosticMessage = diagnosticMessage
        self.providerErrorCode = providerErrorCode
    }
}
