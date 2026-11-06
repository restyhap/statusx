import Cocoa

// 合成一次左键拖拽：drag <x1> <y1> <x2> <y2> [步数]
// 用于验证设置窗口里的图标拖动排序（mbtool 只能点击，不能拖动）。

let args = CommandLine.arguments
guard args.count >= 5,
      let x1 = Double(args[1]), let y1 = Double(args[2]),
      let x2 = Double(args[3]), let y2 = Double(args[4]) else {
    print("用法: drag x1 y1 x2 y2 [steps]")
    exit(1)
}
let steps = args.count >= 6 ? max(2, Int(args[5]) ?? 24) : 24

let source = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ x: Double, _ y: Double) {
    CGEvent(mouseEventSource: source, mouseType: type,
            mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

post(.mouseMoved, x1, y1)
usleep(60_000)
post(.leftMouseDown, x1, y1)
usleep(120_000)
for i in 1...steps {
    let t = Double(i) / Double(steps)
    post(.leftMouseDragged, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t)
    usleep(25_000)
}
usleep(120_000)
post(.leftMouseUp, x2, y2)
