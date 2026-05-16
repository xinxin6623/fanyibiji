import Foundation

/// 截屏坐标几何（纯函数、零系统依赖、可 100% 单测）。
///
/// T-INT2 真机暴露：AppKit overlay 坐标（原点左下、Y 向上）直接喂
/// `SCStreamConfiguration.sourceRect`（CoreGraphics 显示坐标：原点
/// 左上、Y 向下）会上下镜像，截到错误区域（空白）→ OCR 无文字，
/// 且失败伪装成"OCR 没识别"。把翻转逻辑从 `SCScreenCapturer`（系统
/// 边界、不可测）抽到此处，加多屏/高分/边界单测，防回归。
enum ScreenGeometry {

    /// 把 AppKit 选区矩形翻成 CoreGraphics 显示坐标。
    ///
    /// - Parameters:
    ///   - appKitRect: overlay 给出的选区（原点左下、Y 向上，单位 point，
    ///     已是目标显示器的局部坐标）。
    ///   - displayHeight: 目标显示器高度（point）。
    /// - Returns: `sourceRect` 用的 CG 矩形（原点左上、Y 向下）。
    ///   `cgY = displayHeight - appKitY - height`。x/宽/高不变。
    static func flipToCGDisplayRect(appKitRect: CGRect,
                                    displayHeight: CGFloat) -> CGRect {
        CGRect(
            x: appKitRect.origin.x,
            y: displayHeight - appKitRect.origin.y - appKitRect.height,
            width: appKitRect.width,
            height: appKitRect.height)
    }

    /// 像素尺寸 = 选区 point 尺寸 × 缩放（高分屏 backingScaleFactor）。
    /// 至少 1 像素，避免 0 尺寸截图请求。
    static func pixelSize(forPointSize size: CGSize,
                          scale: Double) -> (width: Int, height: Int) {
        (max(1, Int((size.width * scale).rounded())),
         max(1, Int((size.height * scale).rounded())))
    }
}
