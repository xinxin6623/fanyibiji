import Foundation

enum InputSourceKind: String, Codable, Sendable {
    case screenshot
    case selectedText
    case clipboard
    case manualInput
}

struct DisplayInfo: Sendable, Equatable {
    let scaleFactor: Double
    let pixelSize: CGSize
}

enum InputSource: Sendable {
    case screenshot(image: Data, display: DisplayInfo)
    case selectedText(String)
    case clipboard(String)
    case manualInput(String)

    var kind: InputSourceKind {
        switch self {
        case .screenshot: return .screenshot
        case .selectedText: return .selectedText
        case .clipboard: return .clipboard
        case .manualInput: return .manualInput
        }
    }
}
