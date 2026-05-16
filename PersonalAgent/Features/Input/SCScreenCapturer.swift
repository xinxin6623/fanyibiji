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

        // 坐标系翻转抽到 `ScreenGeometry`（纯函数、有多屏/高分/边界
        // 单测，防 T-INT2 那类坐标回归再次静默截空白）。
        let cgRect = ScreenGeometry.flipToCGDisplayRect(
            appKitRect: region.rect,
            displayHeight: CGFloat(display.height))
        let px = ScreenGeometry.pixelSize(
            forPointSize: region.rect.size, scale: scale)

        let config = SCStreamConfiguration()
        config.sourceRect = cgRect
        config.width = px.width
        config.height = px.height

        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
        } catch is CancellationError {
            throw AgentError(category: .cancelled, diagnosticMessage: "capture cancelled")
        } catch {
            throw AgentError(category: .unknown, diagnosticMessage: "capture failed")
        }

        // 空图防御：截到近纯色 → 多半是坐标翻转/采集异常（T-INT2 那类
        // 根因）。明确报"疑似空白/坐标异常"而非让下游 OCR 报"无文字"
        // 掩盖根因。判定逻辑在纯函数 `BlankImageDetector`（可单测）。
        if let rgba = Self.rgbaBytes(from: cgImage),
           BlankImageDetector.isNearlyBlank(
               rgba: rgba, width: cgImage.width, height: cgImage.height) {
            throw AgentError(
                category: .invalidInput,
                diagnosticMessage:
                    "captured image nearly blank — likely coord/capture error")
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

    /// 把 CGImage 解到 RGBA8888 连续缓冲，供 `BlankImageDetector` 采样。
    /// 失败返回 nil（此时跳过空图检测，不阻断截图——宁可漏报不误杀）。
    private static func rgbaBytes(from image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = buf.withUnsafeMutableBytes({ ptr in
                  CGContext(
                      data: ptr.baseAddress,
                      width: w, height: h,
                      bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: cs,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
              }) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buf
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
