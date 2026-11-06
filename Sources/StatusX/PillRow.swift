import Cocoa

/// 状态组件那一行：胶囊可点（开关）、可拖动（改显示顺序）。
/// 顺序写进 `metricOrder`，状态栏按这个顺序排布。
final class PillRow: NSView {

    struct Item {
        let kind: MetricKind
        let title: String
        let on: Bool
        let enabled: Bool
    }

    var items: [Item] = []
    var onToggle: ((MetricKind, Bool) -> Void)?
    var onReorder: (([MetricKind]) -> Void)?

    private var pills: [DraggablePill] = []
    private var dragKind: MetricKind?
    private let spacing: CGFloat = 6
    private let pillH: CGFloat = 24

    override var isFlipped: Bool { true }

    /// 外部设置 items 后调用：重建胶囊
    func reload() {
        rebuild()
    }

    private func rebuild() {
        pills.forEach { $0.removeFromSuperview() }
        pills = items.map { item in
            let p = DraggablePill(title: item.title)
            p.kind = item.kind
            p.row = self
            p.state = item.on ? .on : .off
            p.isEnabled = item.enabled
            p.needsDisplay = true
            addSubview(p)
            return p
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        applyFrames(animated: false)
    }

    private func applyFrames(animated: Bool) {
        var x: CGFloat = 0
        var frames: [NSRect] = []
        for p in pills {
            let w = p.fittingWidth()
            frames.append(NSRect(x: x, y: 0, width: w, height: pillH))
            x += w + spacing
        }
        guard animated else {
            for (p, f) in zip(pills, frames) { p.frame = f }
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for (p, f) in zip(pills, frames) { p.animator().frame = f }
        }
    }

    override var intrinsicContentSize: NSSize {
        let total = pills.reduce(CGFloat(0)) { $0 + $1.fittingWidth() } + spacing * CGFloat(max(0, pills.count - 1))
        return NSSize(width: max(total, 1), height: pillH)
    }

    // MARK: - 点击 / 拖动

    fileprivate func handleMouse(_ pill: DraggablePill) {
        guard pill.isEnabled, let kind = pill.kind else { return }
        dragKind = kind
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            pill.animator().alphaValue = 0.85
        }
        var moved = false

        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseUp { break }
            moved = true
            let p = convert(e.locationInWindow, from: nil)
            moveDragged(to: p.x)
        }
        dragKind = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            pill.animator().alphaValue = 1
        }

        if !moved {
            let now = (pill.state == .on) ? false : true
            pill.state = now ? .on : .off
            pill.needsDisplay = true
            // 同步数据源，避免下次重建又回到旧状态
            if let i = items.firstIndex(where: { $0.kind == kind }) {
                items[i] = Item(kind: kind, title: items[i].title, on: now, enabled: items[i].enabled)
            }
            onToggle?(kind, now)
        } else {
            onReorder?(items.map { $0.kind })
        }
    }

    private func moveDragged(to x: CGFloat) {
        guard let kind = dragKind,
              let from = items.firstIndex(where: { $0.kind == kind }) else { return }
        var target = items.count - 1
        for (i, p) in pills.enumerated() where x < p.frame.midX {
            target = i
            break
        }
        guard target != from else { return }

        // 只交换数组顺序 + 动画到新槽位，不整行重建（重建会闪一下）
        let item = items.remove(at: from)
        items.insert(item, at: target)
        let pill = pills.remove(at: from)
        pills.insert(pill, at: target)
        applyFrames(animated: true)
    }
}

/// 可拖动胶囊（复用 TogglePill 的三态外观，鼠标事件交给 PillRow 处理）
final class DraggablePill: TogglePill {
    var kind: MetricKind?
    weak var row: PillRow?

    override func mouseDown(with event: NSEvent) {
        row?.handleMouse(self)
    }
}
