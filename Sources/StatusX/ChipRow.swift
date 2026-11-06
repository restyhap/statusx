import Cocoa

/// 一行胶囊标签：可点、可删（×）、可拖动换序。
/// 用来编辑「这个组件要显示哪些数值」——拖动即调整带子里的显示顺序。
final class ChipRow: NSView {

    struct Chip {
        let id: String
        let title: String
    }

    var chips: [Chip] = [] { didSet { rebuild() } }
    /// 点整块（用于「可用」里点击添加）
    var onTap: ((String) -> Void)?
    /// 点 × （用于「已选」里移除）
    var onRemove: ((String) -> Void)?
    /// 拖动后的新顺序
    var onReorder: ((_ ids: [String]) -> Void)?

    private var buttons: [ChipButton] = []
    private var dragIndex: Int?
    private var dragStartX: CGFloat = 0
    private let chipH: CGFloat = 24
    private let gap: CGFloat = 6

    override var isFlipped: Bool { true }

    private func rebuild() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = chips.map { chip in
            let b = ChipButton(title: chip.title, removable: onRemove != nil)
            b.chipID = chip.id
            b.target = self
            b.action = #selector(chipTapped(_:))
            addSubview(b)
            return b
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    @objc private func chipTapped(_ sender: ChipButton) {
        if let id = sender.chipID { onTap?(id) }
    }

    @objc fileprivate func removeTapped(_ sender: ChipButton) {
        if let id = sender.chipID { onRemove?(id) }
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for b in buttons {
            let w = b.fittingWidth()
            b.frame = NSRect(x: x, y: 0, width: w, height: chipH)
            x += w + gap
        }
    }

    override var intrinsicContentSize: NSSize {
        let total = buttons.reduce(CGFloat(0)) { $0 + $1.fittingWidth() } + gap * CGFloat(max(0, buttons.count - 1))
        return NSSize(width: max(total, 1), height: chipH)
    }

    // MARK: - 拖拽换序

    fileprivate func beginDrag(_ button: ChipButton, event: NSEvent) {
        guard let idx = buttons.firstIndex(of: button) else { return }
        dragIndex = idx
        dragStartX = button.frame.minX
        window?.makeFirstResponder(nil)
    }

    fileprivate func continueDrag(_ button: ChipButton, event: NSEvent) {
        guard let from = dragIndex else { return }
        let p = convert(event.locationInWindow, from: nil)
        // 目标位置：按鼠标 x 找最近的槽位
        var target = buttons.count - 1
        for (i, b) in buttons.enumerated() where p.x < b.frame.midX {
            target = i
            break
        }
        guard target != from else { return }
        var order = buttons.map { $0.chipID ?? "" }
        let moved = order.remove(at: from)
        order.insert(moved, at: target)
        dragIndex = target
        applyOrder(order)
    }

    fileprivate func endDrag() {
        dragIndex = nil
        onReorder?(buttons.compactMap { $0.chipID })
    }

    /// 按给定顺序重排 chips 并重建视图
    private func applyOrder(_ order: [String]) {
        let map = Dictionary(uniqueKeysWithValues: chips.map { ($0.id, $0) })
        let newChips = order.compactMap { map[$0] }
        if newChips.count == chips.count {
            chips = newChips
        }
    }
}

/// 单个胶囊：左边是标题，可删时右边带 ×
final class ChipButton: NSButton {

    var chipID: String?
    private let removable: Bool
    private var closeBox: NSRect = .zero

    init(title: String, removable: Bool) {
        self.removable = removable
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        font = .systemFont(ofSize: 12)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("不支持 nib") }

    func fittingWidth() -> CGFloat {
        let w = (title as NSString).size(withAttributes: [.font: font ?? .systemFont(ofSize: 12)]).width
        return ceil(w) + (removable ? 34 : 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: 7, yRadius: 7)
        (isHighlighted ? NSColor.quaternaryLabelColor : NSColor.controlBackgroundColor).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        let textX = removable ? 10 : (bounds.width - size.width) / 2
        (title as NSString).draw(at: NSPoint(x: textX, y: (bounds.height - size.height) / 2),
                                 withAttributes: attrs)

        if removable {
            closeBox = NSRect(x: bounds.width - 20, y: (bounds.height - 12) / 2, width: 12, height: 12)
            NSColor.secondaryLabelColor.setStroke()
            let p = NSBezierPath()
            p.lineWidth = 1.2
            p.move(to: NSPoint(x: closeBox.minX + 3, y: closeBox.minY + 3))
            p.line(to: NSPoint(x: closeBox.maxX - 3, y: closeBox.maxY - 3))
            p.move(to: NSPoint(x: closeBox.maxX - 3, y: closeBox.minY + 3))
            p.line(to: NSPoint(x: closeBox.minX + 3, y: closeBox.maxY - 3))
            p.stroke()
        }
    }

    /// 自带跟踪：点击=选中，拖动=换序（自定义跟踪，NSButton 自己的 tracking 会吞掉拖动）
    override func mouseDown(with event: NSEvent) {
        guard let row = superview as? ChipRow else {
            super.mouseDown(with: event)
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        if removable, closeBox.contains(p) {
            row.removeTapped(self)
            return
        }
        row.beginDrag(self, event: event)
        var moved = false
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if e.type == .leftMouseDragged {
                moved = true
                row.continueDrag(self, event: e)
            } else {
                break
            }
        }
        row.endDrag()
        if !moved, let id = chipID { row.onTap?(id) }
    }
}
