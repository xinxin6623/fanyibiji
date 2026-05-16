import XCTest
@testable import PersonalAgent

/// T12-A 截屏空图/坐标防御单测。
///
/// 覆盖坐标翻转纯函数（多屏/高分/边界）与近纯色检测，回归提前拦截
/// T-INT2 那类"坐标错→静默截空白→OCR 伪装无文字"。系统采集层
/// （`SCScreenCapturer`）仍属真机边界不单测，逻辑已下沉到本两纯函数。
final class T12ScreenDefenseTests: XCTestCase {

    // MARK: ScreenGeometry 坐标翻转

    func testFlipBottomLeftToTopLeft() {
        // AppKit 选区在屏幕下方（y 小，原点左下），翻成 CG 后 y 应变大
        // （原点左上）。display 高 900，选区 y=100 h=40 → cgY=900-100-40=760。
        let r = ScreenGeometry.flipToCGDisplayRect(
            appKitRect: CGRect(x: 50, y: 100, width: 200, height: 40),
            displayHeight: 900)
        XCTAssertEqual(r, CGRect(x: 50, y: 760, width: 200, height: 40))
    }

    func testFlipTopOfScreen() {
        // 选区贴屏幕顶部（AppKit y 大）→ CG y 接近 0。
        let r = ScreenGeometry.flipToCGDisplayRect(
            appKitRect: CGRect(x: 0, y: 860, width: 100, height: 40),
            displayHeight: 900)
        XCTAssertEqual(r, CGRect(x: 0, y: 0, width: 100, height: 40))
    }

    func testFlipIsInvolutive() {
        // 翻两次应回到原矩形（翻转是对合运算）。
        let orig = CGRect(x: 12, y: 345, width: 67, height: 89)
        let once = ScreenGeometry.flipToCGDisplayRect(
            appKitRect: orig, displayHeight: 1080)
        let twice = ScreenGeometry.flipToCGDisplayRect(
            appKitRect: once, displayHeight: 1080)
        XCTAssertEqual(twice, orig)
    }

    func testPixelSizeAppliesScaleAndFloors() {
        // 2x Retina：100x40 point → 200x80 px。
        let p = ScreenGeometry.pixelSize(
            forPointSize: CGSize(width: 100, height: 40), scale: 2)
        XCTAssertEqual(p.width, 200)
        XCTAssertEqual(p.height, 80)
    }

    func testPixelSizeAtLeastOne() {
        // 退化尺寸不产生 0 像素请求。
        let p = ScreenGeometry.pixelSize(
            forPointSize: CGSize(width: 0.2, height: 0.2), scale: 1)
        XCTAssertEqual(p.width, 1)
        XCTAssertEqual(p.height, 1)
    }

    // MARK: BlankImageDetector 近纯色检测

    private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8,
                       w: Int, h: Int) -> [UInt8] {
        var px = [UInt8]()
        px.reserveCapacity(w * h * 4)
        for _ in 0..<(w * h) { px += [r, g, b, 255] }
        return px
    }

    func testPureWhiteIsBlank() {
        XCTAssertTrue(BlankImageDetector.isNearlyBlank(
            rgba: solid(255, 255, 255, w: 64, h: 64),
            width: 64, height: 64))
    }

    func testPureBlackIsBlank() {
        XCTAssertTrue(BlankImageDetector.isNearlyBlank(
            rgba: solid(0, 0, 0, w: 64, h: 64), width: 64, height: 64))
    }

    func testNearSolidWithinToleranceIsBlank() {
        // 整图在 ±4 抖动，低于默认 tolerance 8 → 仍判空白。
        var px = solid(120, 120, 120, w: 64, h: 64)
        for i in stride(from: 0, to: px.count, by: 4) {
            px[i] = UInt8(118 + (i / 4) % 5)   // 118..122
        }
        XCTAssertTrue(BlankImageDetector.isNearlyBlank(
            rgba: px, width: 64, height: 64))
    }

    func testImageWithContrastIsNotBlank() {
        // 一半白一半黑（有文字/内容的典型对比）→ 非空白。
        var px = [UInt8]()
        for y in 0..<64 {
            for _ in 0..<64 {
                let v: UInt8 = y < 32 ? 255 : 0
                px += [v, v, v, 255]
            }
        }
        XCTAssertFalse(BlankImageDetector.isNearlyBlank(
            rgba: px, width: 64, height: 64))
    }

    func testTooShortBufferTreatedAsBlank() {
        // 缓冲长度不足（采集异常）→ 保守判空白（疑似异常）。
        XCTAssertTrue(BlankImageDetector.isNearlyBlank(
            rgba: [0, 0, 0, 255], width: 64, height: 64))
    }

    func testZeroSizeTreatedAsBlank() {
        XCTAssertTrue(BlankImageDetector.isNearlyBlank(
            rgba: [], width: 0, height: 0))
    }
}
