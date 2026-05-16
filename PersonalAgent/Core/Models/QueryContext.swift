import Foundation

enum UserAction: String, Codable, Sendable {
    case query
    case translate
    case speak
}

struct QueryContext: Codable, Sendable, Equatable {
    let id: UUID
    let sourceKind: InputSourceKind
    let inputText: String
    let createdAt: Date
    let languageHints: [String]
    let userAction: UserAction

    init(
        id: UUID = UUID(),
        sourceKind: InputSourceKind,
        inputText: String,
        createdAt: Date = Date(),
        languageHints: [String] = [],
        userAction: UserAction
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.inputText = inputText
        self.createdAt = createdAt
        self.languageHints = languageHints
        self.userAction = userAction
    }
}
