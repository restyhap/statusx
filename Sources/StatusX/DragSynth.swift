import Cocoa
import ApplicationServices

/// 只保留「合成一次点击」：把面板里的选择落到真实状态项上（官方公开的 CGEvent）。
///
/// 2026-10-30 定案：不再用合成 ⌘-拖拽调整任何菜单栏项的顺序 —— 顺序交给用户手动 ⌘ + 拖拽。
enum DragSynth {

    /// 点一下某个屏幕坐标（CG 坐标，左上原点）；点完把光标送回原处，不让鼠标被“带走”。
    static func click(at point: CGPoint) {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        let home = cursor()
        warp(to: point, src: src)
        Thread.sleep(forTimeInterval: 0.02)
        if let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                              mouseCursorPosition: point, mouseButton: .left) {
            down.post(tap: .cghidEventTap)
        }
        Thread.sleep(forTimeInterval: 0.04)
        if let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                            mouseCursorPosition: point, mouseButton: .left) {
            up.post(tap: .cghidEventTap)
        }
        restore(home, after: point, src: src)
    }

    // MARK: - 光标保护

    private static func cursor() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// warp 本身不产生事件，必须补一个 delta=0 的 moved 事件，否则窗口服务器还以为光标在原处。
    private static func warp(to p: CGPoint, src: CGEventSource) {
        CGWarpMouseCursorPosition(p)
        CGAssociateMouseAndMouseCursorPosition(1)
        guard let m = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                              mouseCursorPosition: p, mouseButton: .left) else { return }
        m.setIntegerValueField(.mouseEventDeltaX, value: 0)
        m.setIntegerValueField(.mouseEventDeltaY, value: 0)
        m.post(tap: .cghidEventTap)
    }

    /// 只有「光标还停在我们离开的位置」才送回去——用户自己已经挪走就不抢。
    private static func restore(_ home: CGPoint?, after end: CGPoint, src: CGEventSource) {
        guard let home, let now = cursor() else { return }
        guard hypot(now.x - end.x, now.y - end.y) < 40 else { return }
        warp(to: home, src: src)
    }
}
