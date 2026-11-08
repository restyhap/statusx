import Cocoa

/// 翻转坐标的容器：让滚动视图里的内容从上往下排
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// 白底模式的背景：极浅的蓝白渐变
final class GradientBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        path.addClip()
        NSGradient(starting: NSColor(calibratedRed: 0.89, green: 0.95, blue: 0.99, alpha: 1),
                   ending: NSColor.white)?.draw(in: bounds, angle: -90)
    }
}

/// 面板里的一张卡片：圆角、细边、内部竖直堆叠
final class CardView: NSView {
    private let stack = NSStackView()

    init(spacing: CGFloat = 8, padding: CGFloat = 14) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor(calibratedWhite: 0.45, alpha: 0.18).cgColor
        layer?.backgroundColor = NSColor.white.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding)
        ])
    }

    required init?(coder: NSCoder) { fatalError("不支持 nib") }

    /// 加一行满宽内容
    func addRow(_ view: NSView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}

// MARK: - 小工具

func sxLabel(_ text: String,
             size: CGFloat = 12,
             weight: NSFont.Weight = .regular,
             color: NSColor = .labelColor) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    return l
}

func sxHStack(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .horizontal
    s.alignment = .centerY
    s.spacing = spacing
    return s
}

func sxSpacer() -> NSView {
    let v = NSView()
    v.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
    return v
}

func sxDivider() -> NSBox {
    let b = NSBox()
    b.boxType = .separator
    return b
}

/// 一列指标：上面小标题，下面数值
private func metric(_ title: String, _ value: String) -> NSView {
    let v = NSStackView(views: [sxLabel(title, size: 10.5, color: .secondaryLabelColor),
                                sxLabel(value, size: 13, weight: .medium)])
    v.orientation = .vertical
    v.alignment = .leading
    v.spacing = 2
    return v
}

/// 退出进程：GUI App 走优雅退出，命令行/守护进程退回 SIGTERM
enum Panel {
    /// 绝对不能碰的进程（杀了会注销/黑屏/内核崩溃）
    private static let forbidden: Set<String> = [
        "launchd", "kernel_task", "WindowServer", "loginwindow", "Finder",
        "Dock", "SystemUIServer", "ControlCenter", "NotificationCenter",
        "logind", "runningboardd", "bash", "zsh", "Terminal"
    ]

    /// 关掉一个应用的全部进程；返回可读的结果（失败时带原因）
    static func quit(pids: [Int32], name: String) -> String {
        var ok = 0
        var reasons: [String] = []
        for pid in pids {
            // 用该进程自己的名字校验（同一个 App 的 Helper 进程名各不相同，拿组名去比会对不上）
            var buf = [CChar](repeating: 0, count: 256)
            let own = proc_name(pid, &buf, 256) > 0 ? String(cString: buf) : name
            let r = quit(pid: pid, name: own)
            if r.hasPrefix("已") { ok += 1 } else { reasons.append(r) }
        }
        if ok > 0 {
            if reasons.isEmpty { return "已退出（\(ok) 个进程）" }
            return "已退出 \(ok) 个；\(reasons[0])"
        }
        return reasons.first ?? "失败：没有可结束的进程"
    }

    /// 取进程的可执行路径
    static func executablePath(_ pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buf, 4096) > 0 else { return nil }
        return String(cString: buf)
    }

    /// 结束后 2.5 秒复查：真退出了才说退出（mysqld 这类要刷盘，几秒才走）
    static func watchExit(name: String, report: @escaping (String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            report(processExists(named: name) ? "\(name) 仍在运行（可能正在关闭）" : "\(name) 已退出")
        }
    }

    /// 结束后 0.5 秒回头看：同名的又起来了 → 说明是服务型进程（launchd / brew services 托管）
    static func watchRestart(name: String, report: @escaping (String) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if processExists(named: name) {
                report("\(name) 已被重新拉起（服务类进程，需用 brew services 停止）")
            }
        }
    }

    private static func processExists(named name: String) -> Bool {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard n > 0 else { return false }
        for i in 0..<Int(n) {
            var buf = [CChar](repeating: 0, count: 256)
            guard proc_name(pids[i], &buf, 256) > 0 else { continue }
            if String(cString: buf) == name { return true }
        }
        return false
    }

    static func quit(pid: Int32, name: String) -> String {
        guard pid > 1 else { return "拒绝：系统关键进程" }
        if forbidden.contains(name) { return "拒绝：\(name) 是系统关键进程" }

        // pid 可能被复用：核对进程名是否还对得上
        var buf = [CChar](repeating: 0, count: 256)
        let len = proc_name(pid, &buf, 256)
        guard len > 0 else { return "进程已不存在" }
        let current = String(cString: buf)
        guard current == name || name.hasPrefix(current) || current.hasPrefix(name) else {
            return "进程已变化（现在是 \(current)），已取消"
        }

        if let app = NSRunningApplication(processIdentifier: pid) {
            if app.terminate() { return "已请求退出" }
        }
        // 系统里 pid 很小的守护进程不主动 SIGTERM，风险太高
        if pid < 100, NSRunningApplication(processIdentifier: pid) == nil {
            return "拒绝：系统守护进程，不做强制结束"
        }
        if kill(pid, SIGTERM) == 0 { return "已发送 SIGTERM" }
        return "失败：\(String(cString: strerror(errno)))"
    }
}

/// 面板里的滚动区：自己处理滚轮/触控板（在这个非激活面板里 super.scrollWheel 不生效）
final class ListScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let raw = event.scrollingDeltaY
        let step = event.hasPreciseScrollingDeltas ? raw : raw * 12
        guard step != 0 else { return }
        let maxY = max(0, (documentView?.frame.height ?? 0) - contentView.bounds.height)
        let y = min(max(0, contentView.bounds.origin.y - step), maxY)
        contentView.scroll(to: NSPoint(x: 0, y: y))
        reflectScrolledClipView(contentView)

    }
}

/// 卡片右上角的小曲线（CPU 用）
final class SparklineView: NSView {
    var data: [Double] = [] { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard data.count > 1 else { return }
        let path = NSBezierPath()
        path.lineWidth = 1.2
        path.lineJoinStyle = .round
        for (i, v) in data.enumerated() {
            let x = bounds.width * CGFloat(i) / CGFloat(data.count - 1)
            let y = bounds.height * CGFloat(min(1, max(0, v)))
            if i == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
        }
        NSColor.labelColor.withAlphaComponent(0.75).setStroke()
        path.stroke()
    }
}

/// 折叠区面板：卡片式分区（顶部标题栏 + 状态卡片 + 已折叠列表卡片）
final class FoldedPanel: NSPanel, NSWindowDelegate {

    /// 面板要展示的实时数据
    struct Stats {
        var width: CGFloat      // StatusX 自身宽度
        var folded: Int         // 被折进 << 的 App 数
        var kept: Int           // 仍留在栏上的 App 数
    }

    /// 面板背景模式。正式版用 `popover`（系统毛玻璃），测试/截图用 `white`。
    enum Background: String {
        case popover
        case white
    }

    private let panelWidth: CGFloat
    private let maxRows: Int
    private let showStats: Bool

    private let cardInset: CGFloat = 12
    private let cardPadding: CGFloat = 14
    private let rowHeight: CGFloat = 26

    private let root = NSStackView()
    private let scroll = NSScrollView()
    private let doc = FlippedView()
    private let rows = NSStackView()

    private var onOpenSettings: (() -> Void)?
    private var onQuit: (() -> Void)?
    private var onPick: ((MBItem) -> Void)?

    init(background: Background, width: CGFloat, maxRows: Int, showStats: Bool) {
        self.panelWidth = width
        self.maxRows = maxRows
        self.showStats = showStats
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: 260),
                   // 不加 .nonactivatingPanel：非激活面板拿不到点击，里面的按钮（✕ 退出）会失效
                   styleMask: [.borderless],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        // NSPanel 默认「App 失活就隐藏」；我们是没有 Dock 图标的 accessory App，
        // 一失活面板就被藏起来（表现为「几秒后自己消失」）
        hidesOnDeactivate = false
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = self

        let bg: NSView
        switch background {
        case .popover:
            let blur = NSVisualEffectView()
            blur.material = .popover
            blur.blendingMode = .behindWindow
            blur.state = .active
            bg = blur
        case .white:
            bg = GradientBackground()
            // 浅底必须配浅色外观，否则深色模式下的文字会看不见
            appearance = NSAppearance(named: .aqua)
        }
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 12
        bg.layer?.masksToBounds = true
        contentView = bg

        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 10
        // 文档视图用 frame 驱动：滚动视图里再叠 auto layout 容易出现宽度对不上
        root.translatesAutoresizingMaskIntoConstraints = true

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc
        bg.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: bg.topAnchor, constant: cardInset),
            scroll.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: cardInset),
            scroll.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -cardInset),
            scroll.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -cardInset)
        ])

        doc.translatesAutoresizingMaskIntoConstraints = true
        doc.addSubview(root)


    }

    /// 非激活面板默认拿不到 key，里面的按钮就点不动；允许它成为 key
    override var canBecomeKey: Bool { true }

    /// 点面板外面才关；不再用「失焦自动关」——非激活面板经常拿不到 key，
    /// 一失焦就关会导致里面的按钮（✕ 退出进程）根本点不到
    func windowDidResignKey(_ notification: Notification) {
        // 交给 AppController 的外部点击监听处理
    }

    private var toast: NSView?

    /// 操作结果提示：浮在面板底部，2 秒后淡出
    private func showToast(_ text: String) {
        toast?.removeFromSuperview()
        guard let host = contentView else { return }

        // 必须用 wrappingLabel：labelWithString 是单行 cell，设了 lineBreakMode 也不会折行，
        // 结果把面板撑宽
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .white
        label.alignment = .center
        label.isSelectable = false
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        label.preferredMaxLayoutWidth = panelWidth - 48
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        box.layer?.cornerRadius = 6
        box.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        host.addSubview(box)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -6),
            box.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            box.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -10),
            // 固定宽度：长文本换行显示，别把面板撑开
            box.widthAnchor.constraint(equalToConstant: max(120, panelWidth - 28))
        ])
        toast = box

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self, weak box] in
            guard let box else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                box.animator().alphaValue = 0
            } completionHandler: {
                box.removeFromSuperview()
                if self?.toast === box { self?.toast = nil }
            }
        }
    }

    /// 卡片内部可用宽度
    private var contentWidth: CGFloat {
        panelWidth - cardInset * 2 - cardPadding * 2
    }

    private static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    /// 重建内容：标题栏 + 状态卡片 + 已折叠列表卡片
    func rebuild(snapshot: MetricSnapshot,
                 kinds: [MetricKind],
                 settings: [MetricKind: MetricSettings],
                 onOpenSettings: @escaping () -> Void,
                 onQuit: @escaping () -> Void) {

        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit

        // 每次重建都清空旧回调：按钮会被重建，ObjectIdentifier 可能地址复用，
        // 留着旧条目会让新按钮误触到上一轮的 App
        ClickProxy.shared.handlers.removeAll()
        valueLabels.removeAll()
        cpuSpark = nil
        cpuBox = nil
        memBox = nil
        lastSignature = signature(snapshot, kinds: kinds)
        root.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let keepOffset = scroll.contentView.bounds.origin
        root.arrangedSubviews.forEach { $0.removeFromSuperview() }
        root.addArrangedSubview(headerView())
        for card in statusCards(snapshot, kinds: kinds, settings: settings) {
            root.addArrangedSubview(card)
        }

        root.arrangedSubviews.forEach {
            $0.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }

        contentView?.layoutSubtreeIfNeeded()

        // 面板先定宽，再按内容定文档高度；宽度取滚动视图可视宽，卡片才会和外框等宽
        setContentSize(NSSize(width: panelWidth, height: 200))
        contentView?.layoutSubtreeIfNeeded()
        let docW = max(1, scroll.contentView.bounds.width)
        root.frame = NSRect(x: 0, y: 0, width: docW, height: 0)
        root.layoutSubtreeIfNeeded()
        let contentH = max(1, root.fittingSize.height)
        root.frame = NSRect(x: 0, y: 0, width: docW, height: contentH)
        doc.frame = NSRect(x: 0, y: 0, width: docW, height: contentH)

        var maxH = (NSScreen.main?.visibleFrame.height ?? 900) - 120
        if let raw = ProcessInfo.processInfo.environment["STATUSX_PANEL_MAXH"], let v = Double(raw), v > 100 {
            maxH = v   // 调试：强制矮面板验证滚动
        }
        setContentSize(NSSize(width: panelWidth, height: min(contentH + cardInset * 2, maxH)))
        scroll.contentView.scroll(to: keepOffset)
        scroll.reflectScrolledClipView(scroll.contentView)

        if ProcessInfo.processInfo.environment["STATUSX_DEBUG_PANEL"] == "1" {
            let card = root.arrangedSubviews.first
            Log.line("面板几何：panel=\(panelWidth) clip=\(Int(scroll.contentView.bounds.width)) doc=\(Int(doc.frame.width))x\(Int(doc.frame.height)) root=\(Int(root.frame.width)) 首卡=\(card.map { Int($0.frame.width) } ?? -1) 面板高=\(Int(frame.height)) 需要滚动=\(contentH + cardInset * 2 > maxH)")
        }
    }

    /// 数值标签注册表：key = "组件.字段"，刷新时只改文字，不重建视图（重建一次约 100ms）
    private var valueLabels: [String: NSTextField] = [:]
    private var cpuSpark: SparklineView?
    private var lastSignature = ""

    private func reg(_ key: String, _ label: NSTextField) -> NSTextField {
        label.alignment = label.alignment
        valueLabels[key] = label
        return label
    }

    /// 结构签名：只跟「显示哪些组件」有关；进程名单变化交给列表自己换行
    private func signature(_ s: MetricSnapshot, kinds: [MetricKind]) -> String {
        kinds.map(\.rawValue).joined(separator: ",")
    }

    /// 只换列表里的行（名字变了才做），不重建整张卡
    private func rebuildRows(in box: ListBox, rows: [NSView], names: [String]) {
        box.setRows(rows, names: names, width: listContentWidth)
        box.scroll.heightAnchor.constraint(equalToConstant: CGFloat(min(box.visible, max(1, rows.count))) * box.rowHeight)
    }

    /// 把最新采样写进已注册的标签
    private func applyValues(_ s: MetricSnapshot) {
        let bytes = BarStrip.bytesText
        let b = s.battery

        valueLabels["cpu.pct"]?.stringValue = BarStrip.percentText(s.cpu)
        valueLabels["cpu.sys"]?.stringValue = BarStrip.percentText(s.cpuSystem)
        valueLabels["cpu.user"]?.stringValue = BarStrip.percentText(s.cpuUser)
        valueLabels["cpu.nice"]?.stringValue = BarStrip.percentText(s.cpuNice)
        valueLabels["cpu.temp"]?.stringValue = s.cpuTemp.map { "\(Int($0.rounded()))°C" } ?? "—"
        for (i, row) in s.topCPU.enumerated() {
            valueLabels["cpu.row\(i)"]?.stringValue = Self.cpuText(row.value)
        }

        valueLabels["mem.pct"]?.stringValue = BarStrip.percentText(s.memory)
        valueLabels["mem.used"]?.stringValue = bytes(s.memTotal - s.memFree)
        valueLabels["mem.free"]?.stringValue = bytes(s.memFree)
        valueLabels["mem.cached"]?.stringValue = bytes(s.memCached)
        valueLabels["mem.app"]?.stringValue = bytes(s.memApp)
        valueLabels["mem.wired"]?.stringValue = bytes(s.memWired)
        valueLabels["mem.comp"]?.stringValue = bytes(s.memCompressed)
        let total = max(1, s.memTotal)
        for (i, row) in s.topMem.enumerated() {
            valueLabels["mem.row\(i)"]?.stringValue = bytes(row.value)
            valueLabels["mem.rowpct\(i)"]?.stringValue = BarStrip.percentText(row.value / total)
        }

        valueLabels["net.down"]?.stringValue = "↓" + BarStrip.rateText(s.netDown)
        valueLabels["net.up"]?.stringValue = "↑" + BarStrip.rateText(s.netUp)
        valueLabels["net.head"]?.stringValue = "↓" + BarStrip.rateText(s.netDown)

        valueLabels["disk.pct"]?.stringValue = BarStrip.percentText(s.disk)
        valueLabels["disk.used"]?.stringValue = bytes(s.diskTotal - s.diskFree)
        valueLabels["disk.free"]?.stringValue = bytes(s.diskFree)
        valueLabels["disk.total"]?.stringValue = bytes(s.diskTotal)

        if let b {
            valueLabels["bat.pct"]?.stringValue = "\(b.percent)%"
            valueLabels["bat.remain"]?.stringValue = BarStrip.timeText(s.batteryRemaining) ?? ""
            let design = s.batteryDesign ?? 0
            let real = s.batteryMax ?? 0
            valueLabels["bat.health"]?.stringValue =
                design > 0 && real > 0 ? "\(Int((Double(real) / Double(design) * 100).rounded()))%" : "—"
            valueLabels["bat.design"]?.stringValue = s.batteryDesign.map { "\($0) mAh" } ?? "—"
            valueLabels["bat.real"]?.stringValue = s.batteryMax.map { "\($0) mAh" } ?? "—"
            valueLabels["bat.cycles"]?.stringValue = s.batteryCycles.map { "\($0)" } ?? "—"
            valueLabels["bat.condition"]?.stringValue = {
                guard design > 0, real > 0 else { return "—" }
                let h = Double(real) / Double(design)
                if h >= 0.8 { return Str.pnlGood }
                if h >= 0.6 { return Str.pnlFair }
                return Str.pnlPoor
            }()
            valueLabels["bat.charging"]?.stringValue = b.charging ? Str.pnlYes : Str.pnlNo
            valueLabels["bat.power"]?.stringValue = b.onAC ? Str.pnlAdapter : Str.pnlBattery
        }
        if ProcessInfo.processInfo.environment["STATUSX_DEBUG_PANEL"] == "4" {
            Log.line("排行 CPU：" + s.topCPU.map { "\($0.name)=\(Self.cpuText($0.value))" }.joined(separator: ", "))
            Log.line("排行 MEM：" + s.topMem.map { "\($0.name)=\(BarStrip.bytesText($0.value))" }.joined(separator: ", "))
        }
        if ProcessInfo.processInfo.environment["STATUSX_DEBUG_PANEL"] == "2" {
            for (tag, box) in [("cpu", cpuBox), ("mem", memBox)] {
                if let box {
                    Log.line("列表 \(tag)：doc高=\(Int(box.doc.frame.height)) 可视高=\(Int(box.scroll.contentView.bounds.height)) 行数=\(box.stack.arrangedSubviews.count)")
                }
            }
        }
        if let f = s.fan, f > 0 {
            valueLabels["fan.pct"]?.stringValue = BarStrip.fanText(f) + " RPM"
            valueLabels["fan.rpm"]?.stringValue = "\(Int(f.rounded()))"
        }
        cpuSpark?.data = s.history[.cpu] ?? []
    }

    /// 面板开着时用最新采样刷新内容：结构没变就只改数值（不重建视图）
    func refresh(snapshot: MetricSnapshot, kinds: [MetricKind], settings: [MetricKind: MetricSettings]) {
        let sig = signature(snapshot, kinds: kinds)
        if sig == lastSignature, !valueLabels.isEmpty {
            // 进程名单变了才换行，其余只改数值
            let cpuNames = snapshot.topCPU.map(\.name)
            if let box = cpuBox, box.names != cpuNames {
                let rows = snapshot.topCPU.enumerated().map { (i, row) -> NSView in
                    let v = appRow(row.name, Self.cpuText(row.value), pids: row.pids,
                                   canQuit: row.canQuit, keys: ("cpu.row\(i)", ""))
                    v.heightAnchor.constraint(equalToConstant: 24).isActive = true
                    return v
                }
                rebuildRows(in: box, rows: rows, names: cpuNames)
            }
            let memNames = snapshot.topMem.map(\.name)
            if let box = memBox, box.names != memNames {
                let total = max(1, snapshot.memTotal)
                let rows = snapshot.topMem.enumerated().map { (i, row) -> NSView in
                    let v = appRow(row.name, BarStrip.bytesText(row.value),
                                   extra: BarStrip.percentText(row.value / total),
                                   pids: row.pids, canQuit: row.canQuit,
                                   keys: ("mem.row\(i)", "mem.rowpct\(i)"))
                    v.heightAnchor.constraint(equalToConstant: 24).isActive = true
                    return v
                }
                rebuildRows(in: box, rows: rows, names: memNames)
            }
            applyValues(snapshot)
            return
        }
        lastSignature = sig
        rebuild(snapshot: snapshot, kinds: kinds, settings: settings,
                onOpenSettings: { [weak self] in self?.onOpenSettings?() },
                onQuit: { [weak self] in self?.onQuit?() })
        applyValues(snapshot)
    }

    // MARK: - 顶部标题栏

    private func headerView() -> NSView {
        let title = sxLabel("StatusX", size: 14, weight: .bold)
        let ver = sxLabel("v\(Self.version)", size: 11, color: .secondaryLabelColor)
        let prefs = textButton(Str.prefs) { [weak self] in self?.onOpenSettings?() }
        let quit = textButton(Str.quitApp) { [weak self] in self?.onQuit?() }
        let row = sxHStack([title, ver, sxSpacer(), prefs, quit], spacing: 6)
        row.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return row
    }

    private func textButton(_ title: String, action: @escaping () -> Void) -> NSButton {
        let btn = ActionButton(title: title, onClick: action)
        btn.isBordered = false
        btn.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                         .font: NSFont.systemFont(ofSize: 11)])
        btn.contentTintColor = .secondaryLabelColor
        return btn
    }

    // MARK: - 卡片

    // MARK: - 状态卡片（点状态栏看到的内容）

    private func statusCards(_ s: MetricSnapshot, kinds: [MetricKind],
                             settings: [MetricKind: MetricSettings]) -> [NSView] {
        kinds.compactMap { kindCard($0, s) }
    }

    /// 进程 CPU 百分比：小于 10% 保留一位小数，别把 0.4% 显示成 0%
    static func cpuText(_ fraction: Double) -> String {
        let pct = fraction * 100
        if pct <= 0 { return "0%" }
        if pct < 10 { return String(format: "%.1f%%", pct) }
        return "\(Int(pct.rounded()))%"
    }

    private func cardHeader(_ title: String, _ value: String) -> NSView {
        sxHStack([sxLabel(title, size: 13, weight: .bold), sxSpacer(),
                  sxLabel(value, size: 15, weight: .bold)], spacing: 6)
    }

    /// 等分多列指标：首列贴左、末列贴右、中间列居中——三列或四列时两端都能和卡片边缘对齐
    private func evenRow(_ pairs: [(String, String)], keys: [String] = []) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .top
        stack.spacing = 6

        for (i, pair) in pairs.enumerated() {
            let isFirst = i == 0
            let isLast = i == pairs.count - 1
            let textAlign: NSTextAlignment = isFirst ? .left : (isLast ? .right : .center)

            let label = sxLabel(pair.0, size: 10.5, color: .secondaryLabelColor)
            label.alignment = textAlign
            let val = sxLabel(pair.1, size: 13, weight: .medium)
            val.alignment = textAlign
            if i < keys.count, !keys[i].isEmpty { _ = reg(keys[i], val) }

            let col = NSStackView(views: [label, val])
            col.orientation = .vertical
            col.alignment = isFirst ? .leading : (isLast ? .trailing : .centerX)
            col.spacing = 2
            stack.addArrangedSubview(col)
        }
        return stack
    }

    private func kindsRow(_ pairs: [(String, String)]) -> NSView {
        var views: [NSView] = []
        for (i, p) in pairs.enumerated() {
            if i > 0 { views.append(sxSpacer()) }
            views.append(metric(p.0, p.1))
        }
        return sxHStack(views, spacing: 16)
    }

    private func bytes(_ v: Double) -> String { BarStrip.bytesText(v) }

    /// 细进度条（0…1），用于 CPU / 内存 / 硬盘 / 电池的占用
    private func usageBar(_ fraction: Double) -> NSView {
        let track = NSView()
        track.wantsLayer = true
        track.layer?.cornerRadius = 2
        track.layer?.backgroundColor = NSColor(calibratedWhite: 0.5, alpha: 0.18).cgColor
        track.translatesAutoresizingMaskIntoConstraints = false
        track.heightAnchor.constraint(equalToConstant: 4).isActive = true

        let fill = NSView()
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 2
        fill.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.75).cgColor
        fill.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(fill)
        NSLayoutConstraint.activate([
            fill.leadingAnchor.constraint(equalTo: track.leadingAnchor),
            fill.topAnchor.constraint(equalTo: track.topAnchor),
            fill.bottomAnchor.constraint(equalTo: track.bottomAnchor),
            fill.widthAnchor.constraint(equalTo: track.widthAnchor,
                                        multiplier: CGFloat(min(1, max(0.02, fraction))))
        ])
        return track
    }

    /// 卡片里的可滚动列表；refresh 时只换行、不重建整张卡
    final class ListBox {
        let scroll = ListScrollView()
        let doc = FlippedView()
        let stack = NSStackView()
        var names: [String] = []
        let visible: Int
        let rowHeight: CGFloat

        init(visible: Int, rowHeight: CGFloat) {
            self.visible = visible
            self.rowHeight = rowHeight
        }

        func setRows(_ views: [NSView], names: [String], width: CGFloat) {
            stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
            for v in views { stack.addArrangedSubview(v) }
            self.names = names
            let h = CGFloat(max(1, views.count)) * rowHeight
            doc.frame = NSRect(x: 0, y: 0, width: width, height: h)
            stack.frame = NSRect(x: 0, y: 0, width: width, height: h)
            stack.needsLayout = true
            stack.layoutSubtreeIfNeeded()
        }
    }

    /// 列表内容宽：卡片内容宽减去右侧 15pt（悬浮滚动条约 11pt，留 4pt 呼吸，不压 ✕ 也不留大缝）
    private var listContentWidth: CGFloat {
        panelWidth - cardInset * 2 - cardPadding * 2 - 15
    }

    private var cpuBox: ListBox?
    private var memBox: ListBox?

    /// 进程列表：卡片里只露 visible 行，其余在这个小滚动区里滚
    private func makeList(views: [NSView], visible: Int, rowHeight: CGFloat = 24) -> ListBox {
        let box = ListBox(visible: visible, rowHeight: rowHeight)

        box.doc.translatesAutoresizingMaskIntoConstraints = true
        box.stack.orientation = .vertical
        box.stack.alignment = .leading
        box.stack.spacing = 0
        // 纯 frame 驱动：滚动视图里再叠 auto layout，高度会被压回可视区，滚不动
        box.stack.translatesAutoresizingMaskIntoConstraints = true
        box.doc.addSubview(box.stack)

        box.scroll.hasVerticalScroller = true
        box.scroll.drawsBackground = false
        box.scroll.autohidesScrollers = true
        box.scroll.scrollerStyle = .overlay
        box.scroll.documentView = box.doc
        box.scroll.translatesAutoresizingMaskIntoConstraints = false
        box.scroll.heightAnchor.constraint(equalToConstant: CGFloat(min(visible, max(1, views.count))) * rowHeight).isActive = true

        box.setRows(views, names: [], width: listContentWidth)
        return box
    }

    /// 一行进程：名字 + 数值 + 退出按钮
    private func appRow(_ name: String, _ value: String, extra: String? = nil,
                        pids: [Int32], canQuit: Bool = true, keys: (value: String, extra: String)? = nil) -> NSView {
        let label = sxLabel(name, size: 12)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let quit = ActionButton(title: "✕") { [weak self] in
            guard let self else { return }

            // ① launchd 托管的服务：直接 bootout，避免「杀了又被拉起」
            // 组里任何一个进程命中 launchd 服务就按服务处理（Helper 在主进程前面时也能识别）
            if let service = pids.lazy.compactMap({ LaunchServiceScanner.service(forPID: $0) }).first {
                let label = service.isDaemon ? "系统级守护进程" : "用户服务"
                let alert = NSAlert()
                alert.messageText = "停止服务「\(name)」？"
                alert.informativeText = "它是 launchd 托管的\(label)（\(service.label)）。\n停止后不会再被自动拉起，需要时可重新启动服务。"
                alert.addButton(withTitle: "停止服务")
                alert.addButton(withTitle: "取消")
                guard alert.runModal() == .alertFirstButtonReturn else {
                    self.showToast("\(name)：已取消")
                    return
                }
                let r = LaunchServiceScanner.stop(service)
                Log.line("停止服务：\(service.label) → \(r)")
                // bootout 只卸载 job，已经在跑的子孙进程会被 launchd 收养成孤儿，需要再清一遍
                let cleanup = Panel.quit(pids: pids, name: name)
                Log.line("停服务后清理进程：\(name) pids=\(pids) → \(cleanup)")
                let msg = r.hasPrefix("服务已停止") ? "\(r)；\(cleanup)" : r
                self.showToast("\(name)：\(msg)")
                Panel.watchExit(name: name) { [weak self] text in
                    Log.line("退出复查：\(text)")
                    self?.showToast(text)
                }
                return
            }

            // ② 普通应用 / 进程
            let result = Panel.quit(pids: pids, name: name)
            Log.line("点退出：\(name) pids=\(pids) → \(result)")
            self.showToast("\(name)：\(result)")
            if result.hasPrefix("已") {
                Panel.watchRestart(name: name) { [weak self] text in
                    Log.line("重启检测：\(text)")
                    self?.showToast(text)
                }
                Panel.watchExit(name: name) { [weak self] text in
                    Log.line("退出复查：\(text)")
                    self?.showToast(text)
                }
            }
        }
        quit.bezelStyle = .circular
        quit.isBordered = true
        quit.controlSize = .mini
        quit.font = .systemFont(ofSize: 9, weight: .bold)
        quit.contentTintColor = .secondaryLabelColor
        quit.translatesAutoresizingMaskIntoConstraints = false
        quit.widthAnchor.constraint(equalToConstant: 18).isActive = true
        quit.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let valueLabel = sxLabel(value, size: 12, weight: .medium)
        if let keys { _ = reg(keys.value, valueLabel) }
        var views: [NSView] = [label, sxSpacer(), valueLabel]
        if let extra {
            let extraLabel = sxLabel(extra, size: 11, color: .secondaryLabelColor)
            if let keys { _ = reg(keys.extra, extraLabel) }
            views.append(extraLabel)
        }
        // 系统进程不给退出按钮；但仍留出同宽空白，保证数值一列对齐
        if canQuit {
            views.append(quit)
        } else {
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.widthAnchor.constraint(equalToConstant: 18).isActive = true
            spacer.heightAnchor.constraint(equalToConstant: 18).isActive = true
            views.append(spacer)
        }
        return sxHStack(views, spacing: 8)
    }

    private func kindCard(_ kind: MetricKind, _ s: MetricSnapshot) -> NSView? {
        let bytes = BarStrip.bytesText

        switch kind {
        case .cpu:
            guard s.available[.cpu] ?? true else { return nil }
            let card = CardView(spacing: 10)
            let spark = SparklineView()
            spark.data = s.history[.cpu] ?? []
            spark.translatesAutoresizingMaskIntoConstraints = false
            spark.widthAnchor.constraint(equalToConstant: 46).isActive = true
            spark.heightAnchor.constraint(equalToConstant: 16).isActive = true
            cpuSpark = spark
            card.addRow(sxHStack([sxLabel(Str.bandCPU, size: 13, weight: .bold),
                                  sxSpacer(),
                                  reg("cpu.pct", sxLabel(BarStrip.percentText(s.cpu), size: 15, weight: .bold)),
                                  spark], spacing: 10))
            card.addRow(sxDivider())
            card.addRow(evenRow([(Str.pnlSystem, BarStrip.percentText(s.cpuSystem)),
                                 (Str.pnlUser, BarStrip.percentText(s.cpuUser)),
                                 ("Nice", BarStrip.percentText(s.cpuNice)),
                                 (Str.valTemp, s.cpuTemp.map { "\(Int($0.rounded()))°C" } ?? "—")],
                                keys: ["cpu.sys", "cpu.user", "cpu.nice", "cpu.temp"]))
            if !s.topCPU.isEmpty {
                card.addRow(sxDivider())
                let rowViews = s.topCPU.enumerated().map { (i, row) -> NSView in
                    let view = appRow(row.name, Self.cpuText(row.value), pids: row.pids,
                                      canQuit: row.canQuit,
                                      keys: ("cpu.row\(i)", ""))
                    view.heightAnchor.constraint(equalToConstant: 24).isActive = true
                    return view
                }
                let box = makeList(views: rowViews, visible: 5)
                box.names = s.topCPU.map(\.name)
                cpuBox = box
                card.addRow(box.scroll)
            }
            return card

        case .gpu:
            guard s.available[.gpu] ?? true else { return nil }
            let card = CardView(spacing: 10)
            card.addRow(sxHStack([sxLabel(Str.bandGPU, size: 13, weight: .bold), sxSpacer(),
                                  reg("gpu.pct", sxLabel(BarStrip.percentText(s.gpu), size: 15, weight: .bold))]))
            card.addRow(usageBar(s.gpu))
            return card

        case .memory:
            guard s.available[.memory] ?? true else { return nil }
            let card = CardView(spacing: 10)
            card.addRow(sxHStack([sxLabel(Str.bandMemory, size: 13, weight: .bold),
                                  sxSpacer(),
                                  sxLabel(Str.valUsed, size: 10.5, color: .secondaryLabelColor),
                                  reg("mem.used", sxLabel(bytes(s.memTotal - s.memFree), size: 12, weight: .medium)),
                                  sxLabel(Str.valFree, size: 10.5, color: .secondaryLabelColor),
                                  reg("mem.free", sxLabel(bytes(s.memFree), size: 12, weight: .medium))], spacing: 6))
            card.addRow(usageBar(s.memory))
            card.addRow(sxDivider())
            card.addRow(evenRow([(Str.pnlCached, bytes(s.memCached)),
                                 (Str.pnlApp, bytes(s.memApp)),
                                 (Str.pnlWired, bytes(s.memWired)),
                                 (Str.pnlCompressed, bytes(s.memCompressed))],
                                keys: ["mem.cached", "mem.app", "mem.wired", "mem.comp"]))
            if !s.topMem.isEmpty {
                card.addRow(sxDivider())
                let total = max(1, s.memTotal)
                let rowViews = s.topMem.enumerated().map { (i, row) -> NSView in
                    let view = appRow(row.name, bytes(row.value),
                                      extra: BarStrip.percentText(row.value / total),
                                      pids: row.pids, canQuit: row.canQuit,
                                      keys: ("mem.row\(i)", "mem.rowpct\(i)"))
                    view.heightAnchor.constraint(equalToConstant: 24).isActive = true
                    return view
                }
                let box = makeList(views: rowViews, visible: 5)
                box.names = s.topMem.map(\.name)
                memBox = box
                card.addRow(box.scroll)
            }
            return card

        case .network:
            guard s.available[.network] ?? true else { return nil }
            let card = CardView(spacing: 10)
            card.addRow(sxHStack([sxLabel(Str.bandNetwork, size: 13, weight: .bold), sxSpacer(),
                                  reg("net.head", sxLabel("↓" + BarStrip.rateText(s.netDown), size: 15, weight: .bold))]))
            card.addRow(sxDivider())
            card.addRow(evenRow([(Str.valDown, "↓" + BarStrip.rateText(s.netDown)),
                                 (Str.valUp, "↑" + BarStrip.rateText(s.netUp))],
                                keys: ["net.down", "net.up"]))
            return card

        case .disk:
            guard s.available[.disk] ?? true else { return nil }
            let card = CardView(spacing: 10)
            card.addRow(sxHStack([sxLabel(Str.bandDisk, size: 13, weight: .bold), sxSpacer(),
                                  reg("disk.pct", sxLabel(BarStrip.percentText(s.disk), size: 15, weight: .bold))]))
            card.addRow(usageBar(s.disk))
            card.addRow(sxDivider())
            card.addRow(evenRow([(Str.valUsed, bytes(s.diskTotal - s.diskFree)),
                                 (Str.valFree, bytes(s.diskFree)),
                                 (Str.valTotal, bytes(s.diskTotal))],
                                keys: ["disk.used", "disk.free", "disk.total"]))
            let others = s.volumes.dropFirst()
            if !others.isEmpty {
                card.addRow(sxDivider())
                for v in others.prefix(3) {
                    card.addRow(sxHStack([sxLabel(v.name, size: 12, color: .secondaryLabelColor),
                                          sxSpacer(),
                                          sxLabel("U \(bytes(v.used))   F \(bytes(v.free))",
                                                  size: 12, weight: .medium)], spacing: 8))
                }
            }
            return card

        case .battery:
            guard let b = s.battery else { return nil }
            let card = CardView(spacing: 10)

            let remainLabel = reg("bat.remain", sxLabel(BarStrip.timeText(s.batteryRemaining) ?? "",
                                                        size: 12, color: .secondaryLabelColor))
            card.addRow(sxHStack([sxLabel(Str.bandBattery, size: 13, weight: .bold),
                                  sxSpacer(), remainLabel,
                                  reg("bat.pct", sxLabel("\(b.percent)%", size: 15, weight: .bold))], spacing: 8))
            card.addRow(usageBar(Double(b.percent) / 100))
            card.addRow(sxDivider())

            let design = s.batteryDesign ?? 0
            let real = s.batteryMax ?? 0
            let health = design > 0 && real > 0
                ? "\(Int((Double(real) / Double(design) * 100).rounded()))%"
                : "—"
            card.addRow(evenRow([(Str.pnlHealth, health),
                                 (Str.pnlReal, s.batteryMax.map { "\($0) mAh" } ?? "—"),
                                 (Str.pnlDesign, s.batteryDesign.map { "\($0) mAh" } ?? "—")],
                                keys: ["bat.health", "bat.real", "bat.design"]))
            card.addRow(sxDivider())

            let condition: String = {
                guard design > 0, real > 0 else { return "—" }
                let h = Double(real) / Double(design)
                if h >= 0.8 { return Str.pnlGood }
                if h >= 0.6 { return Str.pnlFair }
                return Str.pnlPoor
            }()
            card.addRow(evenRow([(Str.pnlPower, b.onAC ? Str.pnlAdapter : Str.pnlBattery),
                                 (Str.pnlCondition, condition),
                                 (Str.pnlCharging, b.charging ? Str.pnlYes : Str.pnlNo),
                                 (Str.pnlCycles, s.batteryCycles.map { "\($0)" } ?? "—")],
                                keys: ["bat.power", "bat.condition", "bat.charging", "bat.cycles"]))
            return card

        case .fan:
            guard let f = s.fan, f > 0 else { return nil }
            let card = CardView(spacing: 10)
            card.addRow(sxHStack([sxLabel(Str.bandFan, size: 13, weight: .bold), sxSpacer(),
                                  reg("fan.pct", sxLabel(BarStrip.fanText(f) + " RPM", size: 15, weight: .bold))]))
            card.addRow(usageBar(min(1, f / 6000)))
            card.addRow(sxDivider())
            card.addRow(evenRow([(Str.valRPM, "\(Int(f.rounded()))")], keys: ["fan.rpm"]))
            return card
        }
    }



}

/// 自带回调的按钮：不依赖外部映射表，面板重建也不会丢
final class ActionButton: NSButton {
    private var onClick: (() -> Void)?

    convenience init(title: String, onClick: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.onClick = onClick
        target = self
        action = #selector(fire)
    }

    @objc private func fire() { onClick?() }
}

/// 让动态创建的按钮能回调（NSButton 的 target 需要对象 + selector）
final class ClickProxy: NSObject {
    static let shared = ClickProxy()
    var handlers: [ObjectIdentifier: () -> Void] = [:]

    @objc func fire(_ sender: AnyObject) {
        handlers[ObjectIdentifier(sender)]?()
    }
}

/// App 图标缓存。
/// 每次 rebuild 都要给每个折叠项取图标，逐个走 LaunchServices 太慢；
/// 排布结束时后台预热一次，点击弹窗时就全是缓存命中。
final class IconCache {
    static let shared = IconCache()

    private var cache: [String: NSImage] = [:]
    private let lock = NSLock()

    func icon(for bundleID: String) -> NSImage? {
        lock.lock()
        let hit = cache[bundleID]
        lock.unlock()
        if let hit { return hit }

        guard let img = load(bundleID) else { return nil }
        lock.lock()
        cache[bundleID] = img
        lock.unlock()
        return img
    }

    /// 后台预热（不阻塞主线程）
    func prefetch(_ bundleIDs: [String]) {
        lock.lock()
        let miss = Set(bundleIDs).filter { cache[$0] == nil }
        lock.unlock()
        guard !miss.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            for id in miss { _ = self.icon(for: id) }
            Log.line("图标预热 \(miss.count) 个完成")
        }
    }

    private func load(_ bundleID: String) -> NSImage? {
        guard !bundleID.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 16, height: 16)
        return img
    }
}
