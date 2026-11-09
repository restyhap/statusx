import Cocoa

final class AppController: NSObject, NSApplicationDelegate {

    private var item: NSStatusItem!
    private var placer: Placer!
    private var config = Config.load()
    private var panel: FoldedPanel?
    private var settings: SettingsWindowController?
    private var panelKey = ""
    private var busy = false
    /// 图标带里每个应用图标的可点区域
    /// 带子内容相对状态项左缘的偏移（居中后用）
    private var stripHostX: CGFloat = 0
    /// 把带子贴在状态项左边缘的承载视图
    private var stripHost: StripHostView?
    /// 调试红带只加宽一次
    private var debugGrew = false
    /// 上次记日志时的"图标数 / 宽"，避免每次探测都刷一行
    private var lastStripNote = "-"
    /// 上一次渲染的组件顺序（排序变化时做淡入）
    private var lastKinds: [String] = []
    private var probingSpace = false
    /// 菜单栏里实际可用的宽度（别把带子撑到被系统收进 << 里面）
    private var freeSpace: CGFloat = Placer.bandWidth
    /// 最近一次系统指标采样
    private var metricSnapshot = MetricSnapshot.empty
    /// 指标定时器是否在跑
    private var metricsRunning = false

    /// 应用已在运行、用户再次打开时（Dock/`open -a`）：把设置窗口叫出来，
    /// 这样即使状态项被系统折叠、菜单栏上看不到入口，也还能进设置调整。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag || panel?.isVisible != true { openSettings() }
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        L10n.apply(config)
        Log.line("===== StatusX 启动 ===== AX=\(MBar.trusted()) 屏宽=\(MBar.screenRightEdge()) 语言=\(L10n.lang.rawValue) 配置语言=\(config.language ?? "nil")")
        Log.line("配置：带宽固定 \(Int(config.bandWidth))px（菜单栏顺序由用户 ⌘+拖拽自行调整）")

        // 辅助功能权限只影响「读取/点击别人的菜单栏图标」这类旧能力；
        // 指标带子、面板、设置都不需要它——没有权限也必须正常起栏，不能直接 return。
        if !MBar.trusted() {
            Log.line("无辅助功能权限（不影响指标带子与面板，仅菜单栏扫描能力不可用）")
        }

        // 创建时就按设计宽度申请，避免先窄后宽被系统推到刘海左侧（实测：26→310 会落到 x=583）
        item = NSStatusBar.system.statusItem(withLength: Placer.bandWidth)
        if ProcessInfo.processInfo.environment["STATUSX_NO_AUTOSAVE"] != nil {
            item.autosaveName = nil
        } else {
            item.autosaveName = ProcessInfo.processInfo.environment["STATUSX_DEBUG_BAND"] != nil ? "statusx-debug" : "statusx"
        }
        if let sym = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "StatusX") {
            sym.isTemplate = true
            item.button?.image = sym
        } else {
            item.button?.title = "SX"
        }
        configureButton()

        placer = Placer(config: config, item: item)
        placer.onWidthChanged = { [weak self] w in self?.renderStrip(width: w) }
        renderStrip(width: item.length)

        // 系统把状态项排到哪儿由它决定：启动后确认一次，被折叠就明确告诉用户
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.checkFolded()
        }

        // 指标采样：拿到新数据就重画带子（只有启用的组件才采集）
        Metrics.shared.onChange = { [weak self] snap in
            guard let self else { return }
            self.metricSnapshot = snap
            self.renderStrip(width: self.item?.length ?? Placer.bandWidth)
            // 面板开着时同步刷新，看到的才是实时数据
            if let p = self.panel, p.isVisible {
                let tR = CFAbsoluteTimeGetCurrent()
                let tops = Metrics.shared.sampleProcessTops()
                let tB = CFAbsoluteTimeGetCurrent()
                var fresh = snap
                fresh.topCPU = tops.cpu
                fresh.topMem = tops.mem
                p.refresh(snapshot: fresh, kinds: self.enabledMetrics, settings: self.metricSettingsMap)
                if ProcessInfo.processInfo.environment["STATUSX_PROFILE"] == "1" {
                    let tC = CFAbsoluteTimeGetCurrent()
                    Log.line(String(format: "profile 面板刷新：总 %.1f ms（枚举 %.1f / 重建 %.1f）",
                                    (tC - tR) * 1000, (tB - tR) * 1000, (tC - tB) * 1000))
                }
            }
        }
        syncMetrics()

        // 菜单栏明暗跟着系统外观变，标识颜色也要重画
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            BarStrip.resetDarkCache()
            guard let self else { return }
            self.renderStrip(width: self.item?.length ?? 26)
        }

        relayout(reason: "启动")

        // 调试用：STATUSX_OPEN_PANEL=1 启动后直接开面板（菜单栏被挤进 << 时也能截图）
        if ProcessInfo.processInfo.environment["STATUSX_OPEN_PANEL"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.togglePanel()
            }
        }

        // 调试用：SX_OPEN_SETTINGS=1 启动后直接打开设置窗口，方便截图与联调
        if ProcessInfo.processInfo.environment["SX_OPEN_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.openSettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let item { NSStatusBar.system.removeStatusItem(item) }
    }

    // MARK: - 排布

    /// 唯一的“排布”动作：把自己的状态项设成固定宽度。
    /// 不扫描、不拖拽、不改变任何其它菜单栏项（顺序由用户 ⌘ + 拖拽手动调整）。
    private func relayout(reason: String) {
        guard !busy else { return }
        // 调试红带时不做处理，避免长度被覆盖
        if let raw = ProcessInfo.processInfo.environment["STATUSX_DEBUG_BAND"], let dw = Double(raw) {
            renderStrip(width: CGFloat(dw))
            return
        }
        busy = true
        placer.layout(reason: reason) { [weak self] in
            guard let self else { return }
            self.busy = false
            // 后台预热图标，免得点开面板时才逐个查
            DispatchQueue.global(qos: .utility).async {
                let ids = MBar.knownBundleIDs()
                DispatchQueue.main.async { IconCache.shared.prefetch(ids) }
            }
        }
    }

    // MARK: - 菜单栏图标带

    /// 调试用：只在带子两端各画 3px 红条，截图量真实渲染区间（绕开 AX 报的「请求宽度」）
    private func renderDebugBand(_ w: Double) {
        let image = NSImage(size: NSSize(width: w, height: 22), flipped: false) { rect in
            NSColor.systemRed.setFill()
            NSRect(x: 0, y: 0, width: 3, height: rect.height).fill()
            NSRect(x: rect.width - 3, y: 0, width: 3, height: rect.height).fill()
            return true
        }
        item.length = CGFloat(w)
        // 必须走子视图这条真实渲染路径；直接给 button.image 不显示（实测）
        let host: StripHostView
        if let existing = stripHost, existing.superview === item.button {
            host = existing
        } else {
            host = StripHostView()
            host.imageScaling = .scaleNone
            item.button?.addSubview(host)
            stripHost = host
        }
        host.image = image
        host.needsDisplay = true
        host.frame = NSRect(x: 0, y: 0, width: w, height: 22)
        Log.line("调试红带 \(Int(w))px")
    }

    /// 状态项按钮的固定配置。**改 `item.length` 会让系统重建按钮**，
    /// 重建后 target/action 与子视图都会丢，所以每次改完宽度都要重新挂一遍（2026-11-02 实测踩到：整条带子变空白且点不动）
    private func configureButton() {
        guard let b = item.button else { return }
        b.image = nil
        b.title = ""
        b.toolTip = "StatusX"
        b.target = self
        b.action = #selector(togglePanel)
    }

    /// 按当前宽度重画 StatusX 这条带子：内容就是启用的系统指标（大图标 + 两行文字），
    /// 不再画自己的标识——整条带子都可以点开面板。
    private func renderStrip(width: CGFloat) {
        // 调试：STATUSX_DEBUG_BAND=400 → 只在带子两端画红条，用来量「状态项长度到底有没有生效」
        if let raw = ProcessInfo.processInfo.environment["STATUSX_DEBUG_BAND"], let dw = Double(raw), dw > 10 {
            renderDebugBand(dw)
            // 关键实验：先以窄宽度落地，再在运行中加宽，看系统会不会折叠别的项腾位置
            if let grow = ProcessInfo.processInfo.environment["STATUSX_DEBUG_GROW"],
               let gw = Double(grow), gw > 10, !debugGrew {
                debugGrew = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    Log.line("调试加宽 → \(Int(gw))px")
                    self?.renderDebugBand(gw)
                }
            }
            return
        }
        let dark = BarStrip.barIsDark()
        let kinds = enabledMetrics
        let settings = metricSettingsMap

        // 宽度跟着组件数量走：最小 = 一个组件宽，最大 = 310。
        // 用「预留宽度」（按最宽可能值算）而不是当前值，数值跳动不会带着状态项伸缩。
        let fill = config.autoWidth ?? true
        var target = min(Placer.bandWidth, freeSpace)
        if fill, !kinds.isEmpty {
            let all = BarStrip.reserveWidth(metrics: metricSnapshot, items: kinds,
                                            settings: settings, dark: dark)
            let one = kinds.map {
                BarStrip.reserveWidth(metrics: metricSnapshot, items: [$0],
                                      settings: settings, dark: dark)
            }.max() ?? BarStrip.minWidth
            target = min(Placer.bandWidth, max(one, all))
        }
        if abs(item.length - target) > 1 {
            item.length = target
            Log.line("带宽 \(Int(target))px（自适应 · \(kinds.count) 个组件）")
            // 改长度会让系统**异步**重建按钮：下一帧再挂回调与子视图，否则这一轮画在旧按钮上（实测整条空白且点不动）
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.configureButton()
                self.renderStrip(width: target)
            }
            return
        }
        let image = BarStrip.make(dark: dark, metrics: metricSnapshot,
                                  items: kinds,
                                  settings: settings,
                                  maxWidth: target - 2,
                                  fillWidth: fill)
        // 状态项比带子宽时按钮会把自己的图居中；改成贴左的子视图，右侧留白仍整段可点
        item.button?.image = nil
        item.button?.title = ""
        guard let button = item.button else { return }
        let host: StripHostView
        if let existing = stripHost, existing.superview === button {
            host = existing
        } else {
            host = StripHostView()
            host.imageScaling = .scaleNone
            button.addSubview(host)
            stripHost = host
        }
        host.image = image
        // 内容贴左缘：这条 310px 带子右侧是「留给真实应用状态项」的占位区（2026-10-30 改）
        let hostX: CGFloat = 2
        stripHostX = hostX
        if ProcessInfo.processInfo.environment["STATUSX_DEBUG_GEOM"] == "1" {
            Log.line("几何：按钮 \(button.bounds) host \(host.frame) 图像 \(image.size) 屏高 \(NSScreen.screens.first?.frame.height ?? 0) 可见顶 \(NSScreen.screens.first?.visibleFrame.maxY ?? 0)")
        }
        // 画布高度与状态项一致，垂直居中；超出按钮范围会被系统裁掉
        let dy = Double(ProcessInfo.processInfo.environment["STATUSX_STRIP_DY"] ?? "") ?? 0
        host.frame = NSRect(x: hostX,
                            y: (button.bounds.height - BarStrip.imageHeight) / 2 + CGFloat(dy),
                            width: image.size.width,
                            height: BarStrip.imageHeight)


        // 组件顺序/组合变了：淡入一下，避免整条带子“跳”成新顺序
        let kindsKey = kinds.map(\.rawValue)
        if kindsKey != lastKinds, !lastKinds.isEmpty {
            host.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                host.animator().alphaValue = 1
            }
        }
        lastKinds = kindsKey
        button.needsDisplay = true
        if ProcessInfo.processInfo.environment["STATUSX_DEBUG_BTN"] == "1" {
            if let rep = image.tiffRepresentation, let data = NSBitmapImageRep(data: rep)?.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: "/tmp/strip.png"))
            }
            Log.line("bounds \(button.bounds) hidden \(button.isHidden) alpha \(button.alphaValue) window \(button.window != nil) 按钮 \(Unmanaged.passUnretained(button).toOpaque()) target \(button.target != nil) subviews \(button.subviews.count) hostSuper \(host.superview === button) hostAlpha \(host.alphaValue) img \(host.image?.size ?? .zero) frame \(host.frame)")
        }
        let note = "带宽 \(Int(width)) · 自动分配 \(fill ? "开" : "关") · \(kinds.map(\.rawValue).joined(separator: ","))"
        if note != lastStripNote {
            lastStripNote = note
            Log.line("图标带：带宽 \(Int(width)) · 组件 \(kinds.isEmpty ? "无" : kinds.map(\.rawValue).joined(separator: ","))")
        }
    }

    // MARK: - 面板

    @objc private func togglePanel() {
        // 整条 310px 带子都是"开面板"；右侧真实应用图标是别人的状态项，由系统处理点击。
        let now = CFAbsoluteTimeGetCurrent()
        if let p = panel, p.isVisible {
            p.orderOut(nil)
            lastPanelCloseAt = now
            return
        }
        // 「点面板外面关闭」的全局监听会把**同一次点状态项**也当成外部点击：
        // 它先关面板，紧接着这里又会把面板重新打开（表现为「再点也不会隐藏」）。
        // 同一次点击造成的关闭，短时间内不再重开。
        if now - lastPanelCloseAt < 0.4 { return }

        let tops = Metrics.shared.sampleProcessTops()
        metricSnapshot.topCPU = tops.cpu
        metricSnapshot.topMem = tops.mem
        let t0 = CFAbsoluteTimeGetCurrent()
        // 只做差集：退出的丢掉、新开的补扫，其余复用缓存
        let all = MBar.refreshCached()
        let t1 = CFAbsoluteTimeGetCurrent()
        let me = all.first { $0.pid == getpid() }
        let myX = me?.frame.origin.x ?? Self.leftHint(all)
        let limit = Placer.zoneStart
        // `position` = 保持扫描顺序（AX 子元素顺序就是栏上从左到右的真实顺序）；
        // `name` = 按名称排。折叠项的 AX 帧是假坐标，不能按 x 排。
        let foldedRaw = all.filter {
            !$0.isSystemBar && $0.pid != getpid() && ($0.frame.origin.x < limit + 1 || $0.frame.origin.x < myX)
        }
        let folded = (config.panelSort == "position")
            ? foldedRaw
            : foldedRaw.sorted { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }

        let p = panelForConfig()
        p.rebuild(snapshot: metricSnapshot,
                  kinds: enabledMetrics,
                  settings: metricSettingsMap,
                  onOpenSettings: { [weak self] in self?.openSettings() },
                  onQuit: { NSApp.terminate(nil) })

        let maxX = MBar.screenRightEdge() - p.frame.width - 8
        let x = min(max(8, myX - 60), max(8, maxX))
        let y = NSScreen.main!.frame.height - 39 - 8 - p.frame.height
        p.setFrameOrigin(NSPoint(x: x, y: max(8, y)))
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        p.orderFrontRegardless()
        startOutsideClickMonitor()
        Log.line("面板 frame \(p.frame) key=\(p.isKeyWindow)")
        let t2 = CFAbsoluteTimeGetCurrent()
        Log.line(String(format: "弹窗 %.0fms（扫描 %.0fms，%d 项）",
                        (t2 - t0) * 1000, (t1 - t0) * 1000, folded.count))
    }

    /// 按当前配置取面板；外观相关配置变了就重建
    private func panelForConfig() -> FoldedPanel {
        let key = [
            config.panelBackground ?? "popover",
            "\(Int(config.panelWidth ?? 360))",
            "\(config.maxListRows ?? 14)",
            "\(config.showStatsCard ?? true)"
        ].joined(separator: "|")

        if let p = panel, key == panelKey { return p }

        let p = FoldedPanel(background: Self.panelBackground(config.panelBackground),
                            width: CGFloat(config.panelWidth ?? 360),
                            maxRows: config.maxListRows ?? 14,
                            showStats: config.showStatsCard ?? true)
        panel = p
        panelKey = key
        return p
    }

    // MARK: - 偏好设置

    private func openSettings() {
        panel?.orderOut(nil)

        if settings == nil {
            settings = SettingsWindowController(
                config: config,
                relayoutNow: { [weak self] in
                    guard let self else { return }
                    self.relayout(reason: "手动")
                },
                availability: { Metrics.shared.availability() },
                onChange: { [weak self] cfg in self?.applyConfig(cfg) })
        } else {
            settings?.reload(config)
        }

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        settings?.showWindow(nil)
        settings?.window?.makeKeyAndOrderFront(nil)
        settings?.window?.orderFrontRegardless()
        // 调试/截图：SX_SETTINGS_PAGE=widget 直接落在某一页
        if let page = ProcessInfo.processInfo.environment["SX_SETTINGS_PAGE"] {
            settings?.showPage(page)
        }
        Log.line("设置窗口已打开（key=\(settings?.window?.isKeyWindow ?? false)）")
    }

    /// 设置界面改了配置：只同步固定宽度并重画标识。
    /// 增删应用、改顺序都不再触发任何菜单栏操作 —— 位置由用户自己拖。
    private func applyConfig(_ cfg: Config) {
        let oldKey = panelKey
        config = cfg
        placer.apply(cfg)
        syncMetrics()
        renderStrip(width: item?.length ?? Placer.bandWidth)

        // 外观相关配置变了 → 丢弃旧面板，下次点击时重建
        let probe = [
            config.panelBackground ?? "popover",
            "\(Int(config.panelWidth ?? 360))",
            "\(config.maxListRows ?? 14)",
            "\(config.showStatsCard ?? true)",
            L10n.lang.rawValue
        ].joined(separator: "|")
        if probe != oldKey {
            panel?.orderOut(nil)
            panel = nil
        }
        relayout(reason: "设置变更")
    }

    /// 每个组件的显示配置（全局「显示数值」关掉时，强制所有组件不显示文字）
    private var metricSettingsMap: [MetricKind: MetricSettings] {
        let globalText = config.metricValues ?? true
        var map: [MetricKind: MetricSettings] = [:]
        for kind in MetricKind.allCases {
            var s = config.settings(for: kind)
            if !globalText { s.showText = false }
            map[kind] = s
        }
        return map
    }

    /// 启用的组件，顺序跟用户在设置页拖出来的 `metricOrder` 走
    private var enabledMetrics: [MetricKind] {
        let enabled = Set(config.metrics ?? MetricKind.allCases.map(\.rawValue))
        let raw = config.metricOrder ?? MetricKind.allCases.map(\.rawValue)
        var seen = Set<MetricKind>()
        var order: [MetricKind] = []
        for id in raw {
            guard let k = MetricKind(rawValue: id), !seen.contains(k) else { continue }
            seen.insert(k)
            order.append(k)
        }
        order += MetricKind.allCases.filter { !seen.contains($0) }
        return order.filter { enabled.contains($0.rawValue) }
    }

    /// 有组件才跑定时器；全部关闭就停下，避免白耗电
    private func syncMetrics() {
        let need = !enabledMetrics.isEmpty
        if need, !metricsRunning {
            metricsRunning = true
            Log.line("指标：开始采集（\(enabledMetrics.map(\.rawValue).joined(separator: ","))）")
            Metrics.shared.start()
        } else if !need, metricsRunning {
            metricsRunning = false
            Metrics.shared.stop()
            metricSnapshot = .empty
            Log.line("指标：全部关闭，停止采集")
        }
    }

    private var foldChecked = false
    private var foldHintShown = false

    /// 菜单栏里放不下时，macOS 会把整条状态项收进溢出区（`<<` / `>>`），栏上就一片空白。
    /// 宽度怎么调都救不回来（位置由系统决定），所以只确认一次，然后把「怎么让它重新出现」讲清楚。
    private func checkFolded() {
        foldChecked = true
        guard let w = item?.button?.window else { return }
        let f = w.frame
        let visible = f.width > 40 && f.origin.x >= Placer.zoneStart - 2 && f.origin.y > 0
        guard !visible else { return }
        Log.line("带子被系统收进溢出区（窗口 x=\(Int(f.origin.x)) w=\(Int(f.width))，视口左缘 \(Int(Placer.zoneStart))）")
        guard !foldHintShown else { return }
        foldHintShown = true
        DispatchQueue.main.async { [weak self] in self?.showFoldHint() }
    }

    private func showFoldHint() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.alertStyle = .informational
        a.messageText = Str.foldedTitle
        a.informativeText = Str.foldedBody
        a.addButton(withTitle: Str.foldedCompact)
        a.addButton(withTitle: Str.foldedOpenSettings)
        a.addButton(withTitle: Str.foldedOK)
        switch a.runModal() {
        case .alertFirstButtonReturn:  applyCompactMode()
        case .alertSecondButtonReturn: openSettings()
        default: break
        }
    }

    /// 一键回到「一个组件」的最窄形态：菜单栏挤爆时这是唯一能立刻看见的办法
    private func applyCompactMode() {
        guard let first = enabledMetrics.first else { return }
        config.metrics = [first.rawValue]
        config.save()
        shrinkFoldHintShown()
        renderStrip(width: item?.length ?? Placer.bandWidth)
        Log.line("已切到紧凑模式：只保留 \(first.rawValue)")
    }

    /// 切完紧凑模式允许下一次再提示（万一还是放不下）
    private func shrinkFoldHintShown() { foldHintShown = false }

    private var outsideMonitor: Any?
    /// 最近一次关闭面板的时间（挡住同一次点击引起的「关了又开」）
    private var lastPanelCloseAt: CFAbsoluteTime = 0

    /// 点面板以外的地方就关掉（代替「失焦自动关」）
    private func startOutsideClickMonitor() {
        guard outsideMonitor == nil else { return }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self else { return }
            // 点在状态项上：这是「收起面板」的点击，交给 togglePanel，别在这里先关一次
            if let f = self.item?.button?.window?.frame, f.contains(NSEvent.mouseLocation) { return }
            self.lastPanelCloseAt = CFAbsoluteTimeGetCurrent()
            self.panel?.orderOut(nil)
            if let m = self.outsideMonitor {
                NSEvent.removeMonitor(m)
                self.outsideMonitor = nil
            }
        }
    }

    private static func leftHint(_ all: [MBItem]) -> CGFloat {
        Placer.zoneStart
    }

    /// 配置里的背景名 → 面板背景模式；写错或没写都退回正式版的毛玻璃
    private static func panelBackground(_ raw: String?) -> FoldedPanel.Background {
        FoldedPanel.Background(rawValue: raw ?? "popover") ?? .popover
    }

    /// 点折叠项：先收起面板，再用 AXPress 让系统弹它的原生菜单；
    /// 个别 App（如 QQ）AXPress 返回成功却不弹菜单，回退为"展开后真实点击"
    private func pick(_ it: MBItem) {
        panel?.orderOut(nil)
        if ProcessInfo.processInfo.environment["SX_FORCE_FALLBACK"] == "1" {
            Log.line("强制回退路径：\(it.appName)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.revealAndClick(it)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            let err = MBar.press(it.element)
            Log.line("AXPress \(it.appName) → \(err.rawValue)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self else { return }
                guard !Self.hasMenuWindow() else { return }
                Log.line("AXPress 未弹菜单 → 回退：展开后真实点击")
                self.revealAndClick(it)
            }
        }
    }

    /// 回退路径：把 StatusX 缩到最窄（折叠项全部吐出）→ 点它真实坐标 → 菜单关闭后恢复宽度
    private func revealAndClick(_ it: MBItem) {
        guard let item else { return }
        let saved = item.length
        item.length = 26
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            let real = MBar.scanAll().first { $0.pid == it.pid && $0.appName == it.appName }
            guard let real, real.frame.width > 4, real.frame.origin.x > Placer.zoneStart - 2 else {
                Log.line("展开后仍拿不到 \(it.appName) 的真实坐标，放弃")
                item.length = saved
                return
            }
            Log.line("展开后点击 \(it.appName) @ \(Int(real.frame.midX)),\(Int(real.frame.midY))")
            DragSynth.click(at: CGPoint(x: real.frame.midX, y: real.frame.midY))
            self.waitMenuClosed(remaining: 12, saved: saved)
        }
    }

    private func waitMenuClosed(remaining: Double, saved: CGFloat, seen: Bool = false) {
        let open = Self.hasMenuWindow()
        let elapsed = 12 - remaining

        if open {
            schedule(remaining: remaining, saved: saved, seen: true)
            return
        }
        // 菜单已经弹过又关了 → 立刻恢复宽度
        if seen {
            item?.length = saved
            Log.line("菜单已关闭，恢复宽度 \(Int(saved))")
            return
        }
        // 还没见到菜单：给 1.2 秒宽限，再等 3 秒确认没有才放弃
        if elapsed < 1.2 || remaining > 9 {
            schedule(remaining: remaining, saved: saved, seen: false)
            return
        }
        item?.length = saved
        Log.line("\(Int(elapsed))s 内没有菜单窗口，恢复宽度 \(Int(saved))")
    }

    private func schedule(remaining: Double, saved: CGFloat, seen: Bool) {
        guard remaining > 0 else {
            item?.length = saved
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.waitMenuClosed(remaining: remaining - 0.4, saved: saved, seen: seen)
        }
    }

    /// 屏幕上是否还有菜单类窗口（layer ≥ 100）
    static func hasMenuWindow() -> Bool {
        let opts = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { layer in
            let l = layer[kCGWindowLayer as String] as? Int ?? 0
            return l >= 100 && l < 1000   // 菜单窗口是 101；Window Server 的状态指示层是 2^31 量级
        }
    }
}
