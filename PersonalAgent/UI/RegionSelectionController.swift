import AppKit

/// 全屏区域框选 overlay。每个屏幕铺一块半透明无边框窗口，用户拖拽出
/// 矩形，松开 → `RegionSelection.selected`，ESC/右键/空拖拽 → `.cancelled`。
///
/// 坐标契约：`CaptureRegion.fromDrag` 复用 T05 已验证的归一化+裁剪几何，
/// 本类只负责采集拖拽两点（屏幕坐标，point）与所属 displayID/bounds，
/// 不重复实现矩形运算。GUI 需真机手动验收（T-INT2 集中兑现点）。
@MainActor
final class RegionSelectionController {

    private var windows: [NSWindow] = []
    private var continuation: CheckedContinuation<RegionSelection, Never>?

    /// 弹出 overlay 并等待用户选择。保证恰好 resume 一次（多屏只取首个
    /// 完成动作，其余窗口随即拆除）。
    func selectRegion() async -> RegionSelection {
        await withCheckedContinuation { cont in
            self.continuation = cont
            self.presentOverlays()
        }
    }

    private func presentOverlays() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            finish(.cancelled)
            return
        }
        for screen in screens {
            let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber

            let view = RegionSelectionView(
                displayID: displayID?.uint32Value ?? 0,
                // 屏幕在全局坐标系的原点（point），把局部点换算成全局屏幕坐标。
                screenOrigin: screen.frame.origin)
            view.onComplete = { [weak self] selection in
                self?.finish(selection)
            }

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false)
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.18)
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeFirstResponder(windows.first?.contentView)
    }

    private func finish(_ selection: RegionSelection) {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(returning: selection)
    }
}

/// 拖拽采集视图：记录起止点，绘制选区，回传 `RegionSelection`。
private final class RegionSelectionView: NSView {

    var onComplete: ((RegionSelection) -> Void)?

    private let displayID: UInt32
    private let screenOrigin: CGPoint
    private var startPoint: CGPoint?
    private var currentRect: CGRect?

    init(displayID: UInt32, screenOrigin: CGPoint) {
        self.displayID = displayID
        self.screenOrigin = screenOrigin
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = CGRect(
            x: min(start.x, p.x),
            y: min(start.y, p.y),
            width: abs(p.x - start.x),
            height: abs(p.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { startPoint = nil; currentRect = nil; needsDisplay = true }
        guard let start = startPoint else {
            onComplete?(.cancelled)
            return
        }
        let end = convert(event.locationInWindow, from: nil)
        // 局部坐标 → 全局屏幕坐标（point），交给 T05 归一化+裁剪几何。
        let region = CaptureRegion.fromDrag(
            start: CGPoint(x: start.x + screenOrigin.x,
                           y: start.y + screenOrigin.y),
            end: CGPoint(x: end.x + screenOrigin.x,
                         y: end.y + screenOrigin.y),
            displayID: displayID,
            displayBounds: CGRect(origin: screenOrigin, size: bounds.size))
        onComplete?(region.map { .selected($0) } ?? .cancelled)
    }

    override func rightMouseDown(with event: NSEvent) {
        onComplete?(.cancelled)
    }

    override func keyDown(with event: NSEvent) {
        // ESC 取消。
        if event.keyCode == 53 {
            onComplete?(.cancelled)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let rect = currentRect, rect.width >= 1, rect.height >= 1 else {
            return
        }
        NSColor.white.withAlphaComponent(0.12).setFill()
        rect.fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        path.stroke()
    }
}
