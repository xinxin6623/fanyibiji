import Foundation

/// 近纯色（疑似空白/坐标异常）截图检测（纯函数、可单测）。
///
/// T-INT2 真机暴露：坐标翻转错误时截到的是空白图，下游 OCR 报
/// "无文字" → `.invalidInput`，根因被掩盖、需盲查数小时。此检测器
/// 在 OCR 前判定截图是否近纯色，是则报**专用诊断**（`.invalidInput`
/// + diagnosticMessage 标明"疑似空白/坐标异常"），让根因可被一眼归因。
enum BlankImageDetector {

    /// 对 RGBA8888 像素缓冲采样，判断是否近纯色。
    ///
    /// 算法：均匀采样若干像素，统计 RGB 极差（max-min）。整图所有采样
    /// 点的每通道极差都低于阈值即判近纯色。采样而非全扫，O(样本数)。
    ///
    /// - Parameters:
    ///   - rgba: RGBA8888 连续像素（length == width*height*4）。
    ///   - width/height: 像素尺寸。
    ///   - sampleStride: 采样步长（像素），默认每 16 像素取一点。
    ///   - tolerance: 单通道极差阈值（0–255），默认 8（≈3%）。
    /// - Returns: true=近纯色（疑似空白）。
    static func isNearlyBlank(rgba: [UInt8],
                              width: Int,
                              height: Int,
                              sampleStride: Int = 16,
                              tolerance: Int = 8) -> Bool {
        guard width > 0, height > 0,
              rgba.count >= width * height * 4 else {
            // 尺寸非法/缓冲过短：无法判定，保守视为空白（疑似异常）。
            return true
        }
        var rMin = 255, rMax = 0
        var gMin = 255, gMax = 0
        var bMin = 255, bMax = 0
        var sampled = 0
        var y = 0
        while y < height {
            var x = 0
            while x < width {
                let i = (y * width + x) * 4
                let r = Int(rgba[i]), g = Int(rgba[i + 1]), b = Int(rgba[i + 2])
                if r < rMin { rMin = r }; if r > rMax { rMax = r }
                if g < gMin { gMin = g }; if g > gMax { gMax = g }
                if b < bMin { bMin = b }; if b > bMax { bMax = b }
                sampled += 1
                x += sampleStride
            }
            y += sampleStride
        }
        guard sampled > 0 else { return true }
        return (rMax - rMin) <= tolerance
            && (gMax - gMin) <= tolerance
            && (bMax - bMin) <= tolerance
    }
}
