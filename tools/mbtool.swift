import Cocoa
import ApplicationServices

func attr(_ el: AXUIElement, _ n: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, n as CFString, &v) == .success ? v : nil
}
func frame(_ el: AXUIElement) -> CGRect {
    var p = CGPoint.zero, s = CGSize.zero
    if let v = attr(el, kAXPositionAttribute) { _ = AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = attr(el, kAXSizeAttribute) { _ = AXValueGetValue(v as! AXValue, .cgSize, &s) }
    return CGRect(origin: p, size: s)
}

/// 遍历所有 App 的状态栏项
func items() -> [(app: String, bid: String, pid: pid_t, el: AXUIElement, frame: CGRect)] {
    var out: [(String, String, pid_t, AXUIElement, CGRect)] = []
    for app in NSWorkspace.shared.runningApplications {
        guard app.activationPolicy != .prohibited else { continue }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.5)
        guard let barRef = attr(root, kAXExtrasMenuBarAttribute) else { continue }
        guard let kids = attr(barRef as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] else { continue }
        for k in kids {
            out.append((app.localizedName ?? "?", app.bundleIdentifier ?? "?", app.processIdentifier, k, frame(k)))
        }
    }
    return out.sorted { $0.4.origin.x < $1.4.origin.x }
}

/// 点一下某个坐标（CG 坐标），点完把光标送回原处
func click(at p: CGPoint) {
    guard let src = CGEventSource(stateID: .hidSystemState) else { return }
    let home = CGEvent(source: nil)?.location
    func warp(_ q: CGPoint) {
        CGWarpMouseCursorPosition(q)
        CGAssociateMouseAndMouseCursorPosition(1)
        guard let m = CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
                              mouseCursorPosition: q, mouseButton: .left) else { return }
        m.setIntegerValueField(.mouseEventDeltaX, value: 0)
        m.setIntegerValueField(.mouseEventDeltaY, value: 0)
        m.post(tap: .cghidEventTap)
    }
    warp(p)
    Thread.sleep(forTimeInterval: 0.02)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
            mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.04)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
            mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    if let home { warp(home) }
}

let args = CommandLine.arguments
let cmd = args.count > 1 ? args[1] : "scan"
switch cmd {
case "scan":
    for r in items() {
        print(String(format: "x=%4d w=%3d  %-32@ %@", Int(r.frame.origin.x), Int(r.frame.width), r.app as NSString, r.bid))
    }
case "click":
    let x = CGFloat(Double(args.count > 2 ? args[2] : "0") ?? 0)
    let y = CGFloat(Double(args.count > 3 ? args[3] : "13") ?? 13)
    print("点击 (\(Int(x)), \(Int(y)))")
    click(at: CGPoint(x: x, y: y))
default:
    print("用法: mbtool scan | mbtool click <x> <y>")
}
