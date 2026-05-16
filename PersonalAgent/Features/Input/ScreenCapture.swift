import Foundation

/// 截屏区域（屏幕坐标，单位 point）。`fromDrag` 把拖拽两点归一化成
/// 正矩形，并裁剪到目标显示器边界；零面积返回 nil（视为取消/无效）。
struct CaptureRegion: Sendable, Equatable {
    let rect: CGRect
    let displayID: UInt32

    init?(rect: CGRect, displayID: UInt32) {
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        self.rect = rect
        self.displayID = displayID
    }

    /// 由拖拽起止点构造，裁剪进 `displayBounds`。退化（空交集）→ nil。
    static func fromDrag(start: CGPoint,
                         end: CGPoint,
                         displayID: UInt32,
                         displayBounds: CGRect) -> CaptureRegion? {
        let normalized = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y))
        let clipped = normalized.intersection(displayBounds)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else {
            return nil
        }
        return CaptureRegion(rect: clipped, displayID: displayID)
    }
}

/// 截屏产物：PNG 字节 + 显示器元信息（复用 TC `DisplayInfo`），
/// 直接喂 `InputSource.screenshot(image:display:)`。截屏模块只产图，
/// 不调用 LLM/OCR（AGENTS 模块边界）。
struct ScreenshotResult: Sendable, Equatable {
    let imageData: Data
    let display: DisplayInfo
}

/// 系统截屏边界。抽象成协议便于单测注入桩，真实采集走
/// ScreenCaptureKit 薄适配（不在单测触碰真实屏幕/权限）。
protocol ScreenCapturer: Sendable {
    func capture(_ region: CaptureRegion) async throws -> ScreenshotResult
}
