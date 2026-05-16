import Foundation
import CoreGraphics

/// 录屏授权查询边界。抽象成协议便于单测注入授权/拒绝桩，
/// 不在测试中触碰真实系统授权状态或弹系统对话框。
protocol ScreenCaptureAuthorizing: Sendable {
    var isAuthorized: Bool { get }
    /// 触发系统授权请求（首次会弹窗）。返回当下是否已授权。
    @discardableResult
    func requestAccess() -> Bool
}

/// 生产实现：`CGPreflightScreenCaptureAccess` 预检，
/// `CGRequestScreenCaptureAccess` 触发系统授权对话框。
struct SystemScreenCaptureAuthorizer: ScreenCaptureAuthorizing {
    var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }
    @discardableResult
    func requestAccess() -> Bool { CGRequestScreenCaptureAccess() }
}

/// 单测桩。
struct StaticScreenCaptureAuthorizer: ScreenCaptureAuthorizing {
    let isAuthorized: Bool
    @discardableResult
    func requestAccess() -> Bool { isAuthorized }
}
