import Foundation
import AppKit
import ScreenCaptureKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// ScreenCaptureKit 薄适配（系统边界，不做单测；可测逻辑在
/// `CaptureRegion`/`ScreenCaptureCoordinator`，类比 Keychain 先例）。
///
/// 单帧截图用 `SCScreenshotManager`（macOS 14+）。部署目标 13.0：
/// 13.x 上单次截图需 `SCStream` 取帧，属未来硬化范围；此处明确以
/// `AgentError(.unknown)` 报"需 macOS 14"，不静默失败。
struct SCScreenCapturer: ScreenCapturer {

    func capture(_ region: CaptureRegion) async throws -> ScreenshotResult {
        guard #available(macOS 14.0, *) else {
            throw AgentError(category: .unknown,
                             diagnosticMessage: "single-shot capture requires macOS 14")
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
        } catch {
            throw AgentError(category: .permission,
                             diagnosticMessage: "screen content unavailable")
        }
        guard let display = content.displays
            .first(where: { $0.displayID == region.displayID })
            ?? content.displays.first else {
            throw AgentError(category: .unknown,
                             diagnosticMessage: "no shareable display")
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = displayScaleFactor(region.displayID)
        let config = SCStreamConfiguration()
        config.sourceRect = region.rect
        config.width = Int(region.rect.width * scale)
        config.height = Int(region.rect.height * scale)

        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
        } catch is CancellationError {
            throw AgentError(category: .cancelled, diagnosticMessage: "capture cancelled")
        } catch {
            throw AgentError(category: .unknown, diagnosticMessage: "capture failed")
        }

        guard let png = Self.pngData(from: cgImage) else {
            throw AgentError(category: .unknown,
                             diagnosticMessage: "image encode failed")
        }
        let info = DisplayInfo(
            scaleFactor: scale,
            pixelSize: CGSize(width: cgImage.width, height: cgImage.height))
        return ScreenshotResult(imageData: png, display: info)
    }

    private func displayScaleFactor(_ displayID: UInt32) -> Double {
        // 主屏 backingScaleFactor 兜底；多屏精确缩放属后续硬化。
        Double(NSScreen.screens.first?.backingScaleFactor ?? 2.0)
    }

    private static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
