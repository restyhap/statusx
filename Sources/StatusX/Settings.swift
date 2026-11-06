import Cocoa
import ServiceManagement

/// 通用回调盒：把 target/action 转成闭包（窗口每次重建控件都要新建一个）
final class ActionBox: NSObject {
    private let block: (Any?) -> Void
    init(_ block: @escaping (Any?) -> Void) { self.block = block }
    @objc func fire(_ sender: Any?) { block(sender) }
}

/// 左侧栏的一项（对应 HTML 的 li > button）。
/// 不用 NSButton 自带的 image：SF Symbol 的绘制区域大小不一，
/// 自带 image 又没法控制图标与文字间距，所以用固定 16×16 的图标槽 + 固定 8pt 间隔。
final class SidebarButton: NSButton {
    private let iconView = NSImageView()
    private let textLabel = NSTextField(labelWithString: "")

    init(title: String, symbol: String) {
        super.init(frame: .zero)
        // NSButton 程序化创建时自带 "Button" 标题，会跟自绘文字叠在一起；
        // 光设 title 不够，attributedTitle 会保留旧值，一起清掉
        self.title = ""
        alternateTitle = ""
        attributedTitle = NSAttributedString(string: "")
        cell?.title = ""
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 6

        // 所有图标都画在同一个 16×16 的框里，视觉大小才一致
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        textLabel.stringValue = title
        textLabel.font = .systemFont(ofSize: 13)
        textLabel.textColor = .secondaryLabelColor
        textLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(textLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            textLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            textLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("不支持 nib") }

    func setSelected(_ on: Bool) {
        layer?.backgroundColor = on ? NSColor(calibratedWhite: 0.5, alpha: 0.12).cgColor
                                    : NSColor.clear.cgColor
        textLabel.font = .systemFont(ofSize: 13, weight: on ? .semibold : .regular)
        textLabel.textColor = on ? .labelColor : .secondaryLabelColor
        iconView.contentTintColor = on ? .labelColor : .secondaryLabelColor
    }

    /// 子视图（图标/文字）不抢点击，整行都是按钮
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
}

/// 设置窗口用非激活面板：菜单栏工具没有 Dock 图标，普通窗口第一次点击只会"激活"而不会按下控件，
/// 非激活面板可以直接吃下第一次点击（和折叠面板的做法一致）。
final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 偏好设置窗口：左侧栏 + 右侧分页，改动即时生效
final class SettingsWindowController: NSWindowController {

    enum Page: Int, CaseIterable {
        case general, widget, panel, about

        var title: String {
            switch self {
            case .general: return Str.navGeneral
            case .widget:  return Str.navWidget
            case .panel:   return Str.navPanel
            case .about:   return Str.navAbout
            }
        }

        var symbol: String {
            switch self {
            case .general: return "gearshape"
            case .widget:  return "square.grid.2x2"
            case .panel:   return "rectangle.on.rectangle"
            case .about:   return "info.circle"
            }
        }
    }

    private var config: Config
    private let relayoutNow: () -> Void
    private let onChange: (Config) -> Void
    /// 每项指标在本机能不能真实读到数据（不能读到的显示为禁用态）
    private let availability: () -> [MetricKind: Bool]

    /// 左栏宽度：按当前语言最长的分页名算，避免德语/俄语被截断；英文下仍是最窄的 128
    private func sidebarWidth() -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let widest = Page.allCases
            .map { (($0.title) as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 60
        return max(128, ceil(widest) + 10 + 16 + 8 + 24)
    }

    /// 键值行左侧标签列宽：按当前语言最长的那条标签算，行与行仍然对齐
    private func computeRowLabelWidth() -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12)
        let labels = [Str.mode, Str.languageRow, Str.closeAction,
                      Str.background, Str.sortOrder, Str.visibleRows, Str.panelWidth,
                      Str.configFile, Str.runLog, Str.docs]
        let widest = labels
            .map { (($0) as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 60
        return max(88, ceil(widest) + 8)
    }

    private var rowLabelWidth: CGFloat = 88
    private let sidePadding: CGFloat = 10

    private let sidebarBox = NSView()
    private let sidebar = NSStackView()
    private let doc = FlippedView()

    private var sideButtons: [SidebarButton] = []
    private var retained: [ActionBox] = []
    private var page: Page = .general
    /// 状态组件页里正在编辑哪个组件
    private var editingKind: MetricKind = .cpu
    /// 关闭窗口触发的退出只走一次（terminate 会再关一次窗口）
    private var quittingFromClose = false

    init(config: Config,
         relayoutNow: @escaping () -> Void,
         availability: @escaping () -> [MetricKind: Bool] = { [:] },
         onChange: @escaping (Config) -> Void) {
        self.config = config
        self.relayoutNow = relayoutNow
        self.availability = availability
        self.onChange = onChange

        // 先定语言，窗口标题、左栏、页面都要按它取文案
        L10n.apply(config)

        let win = SettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        win.title = Str.winTitle
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 480, height: 360)
        win.setFrameAutosaveName("StatusXSettings")
        // 菜单栏工具没有 Dock 图标、也抢不到激活，普通层级的窗口会落在别的 Space 里点不到；
        // 和折叠面板一样放在状态栏层，保证用户点得到
        win.level = .statusBar
        win.hidesOnDeactivate = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.center()
        super.init(window: win)
        win.delegate = self

        buildChrome()
        show(.general)
    }

    required init?(coder: NSCoder) { fatalError("不支持 nib") }

    /// 每次打开时把外部最新配置同步进来
    func reload(_ cfg: Config) {
        let oldLang = L10n.lang
        config = cfg
        L10n.apply(cfg)
        if L10n.lang != oldLang {
            rebuildChrome()
        } else {
            show(page)
        }
    }

    /// 语言切换后，左栏与当前页都要按新文案重建
    private func rebuildChrome() {
        guard let host = window?.contentView else { return }
        window?.title = Str.winTitle
        host.subviews.forEach { $0.removeFromSuperview() }
        sidebar.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sideButtons.removeAll()
        buildChrome()
        show(page)
    }

    // MARK: - 骨架

    private func buildChrome() {
        guard let win = window, let host = win.contentView else { return }

        // 标签列宽随语言变（俄语/德语比中文长很多）
        rowLabelWidth = computeRowLabelWidth()

        // 左栏：ul 容器（固定宽）+ 竖排 li 按钮（撑满整栏）
        sidebarBox.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(sidebarBox)

        sidebar.orientation = .vertical
        sidebar.alignment = .width         // 按钮等宽撑满整栏
        sidebar.distribution = .fill
        sidebar.spacing = 2
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebarBox.addSubview(sidebar)

        // 中间：一条看得见的分割线
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(divider)

        // 右栏：滚动内容区
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        doc.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = doc
        host.addSubview(scroll)

        for p in Page.allCases {
            let btn = SidebarButton(title: p.title, symbol: p.symbol)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.heightAnchor.constraint(equalToConstant: 32).isActive = true
            btn.target = self
            btn.action = #selector(sideTapped(_:))
            btn.tag = p.rawValue
            sideButtons.append(btn)
            sidebar.addArrangedSubview(btn)
            btn.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            sidebarBox.topAnchor.constraint(equalTo: host.topAnchor),
            sidebarBox.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            sidebarBox.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            sidebarBox.widthAnchor.constraint(equalToConstant: sidebarWidth()),

            sidebar.topAnchor.constraint(equalTo: sidebarBox.topAnchor, constant: 16),
            sidebar.leadingAnchor.constraint(equalTo: sidebarBox.leadingAnchor, constant: sidePadding),
            sidebar.trailingAnchor.constraint(equalTo: sidebarBox.trailingAnchor, constant: -sidePadding),

            divider.topAnchor.constraint(equalTo: host.topAnchor, constant: 12),
            divider.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -12),
            divider.leadingAnchor.constraint(equalTo: sidebarBox.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            scroll.topAnchor.constraint(equalTo: host.topAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 18),
            scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -20),
            scroll.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -16),

            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor)
        ])
    }

    @objc private func sideTapped(_ sender: NSButton) {
        guard let p = Page(rawValue: sender.tag) else { return }
        show(p)
    }

    /// 按名字切页（调试/截图用）：general / widget / panel / about
    func showPage(_ name: String) {
        let map: [String: Page] = ["general": .general, "widget": .widget, "panel": .panel, "about": .about]
        guard let p = map[name.lowercased()] else { return }
        show(p)
    }

    private func show(_ p: Page) {
        page = p
        for btn in sideButtons {
            btn.setSelected(btn.tag == p.rawValue)
        }

        retained.removeAll()
        doc.subviews.forEach { $0.removeFromSuperview() }

        let pane: NSView
        switch p {
        case .general: pane = generalPane()
        case .widget:  pane = widgetPane()
        case .panel:   pane = panelPane()
        case .about:   pane = aboutPane()
        }

        // 页面直接铺满滚动区：每一行再按 leading/trailing 撑满页面，
        // 就不会出现"内容块被挤到右边"的错位
        pane.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(pane)
        NSLayoutConstraint.activate([
            pane.topAnchor.constraint(equalTo: doc.topAnchor),
            pane.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            pane.bottomAnchor.constraint(equalTo: doc.bottomAnchor)
        ])
        doc.layoutSubtreeIfNeeded()
        applyHintWidths(in: pane)
    }

    // MARK: - 配置读写

    private func update(_ mutate: (inout Config) -> Void) {
        let oldLang = config.language
        mutate(&config)
        config.save()
        L10n.apply(config)
        onChange(config)

        // 换语言要把整窗文案重建；放到下一轮循环，避免在 popup 自己的动作里拆掉它
        if config.language != oldLang {
            DispatchQueue.main.async { [weak self] in self?.rebuildChrome() }
        }
    }

    // MARK: - 控件工厂

    private func sectionTitle(_ text: String) -> NSTextField {
        sxLabel(text, size: 13, weight: .bold)
    }

    private func hint(_ text: String) -> NSTextField {
        // 用 wrappingLabelWithString：labelWithString 的 cell 是单行模式，
        // 英文长句不会折行，会横着撑出窗口
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.isSelectable = false
        l.identifier = NSUserInterfaceItemIdentifier("hint")
        l.lineBreakMode = .byWordWrapping
        l.maximumNumberOfLines = 0
        l.preferredMaxLayoutWidth = 340
        return l
    }

    /// 说明文字按内容区宽度折行。必须在视图进了窗口之后再做，
    /// 否则给还没共同祖先的视图加约束会抛 NSException（实测直接崩溃）。
    private func applyHintWidths(in view: NSView) {
        let w = doc.frame.width > 40 ? doc.frame.width : 340
        for sub in view.subviews {
            if let label = sub as? NSTextField, label.identifier?.rawValue == "hint" {
                label.preferredMaxLayoutWidth = w
            }
            applyHintWidths(in: sub)
        }
    }

    private func row(_ title: String, _ control: NSView) -> NSView {
        let label = sxLabel(title, size: 12)
        label.alignment = .left
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: rowLabelWidth).isActive = true
        return sxHStack([label, control, sxSpacer()], spacing: 10)
    }

    private func checkbox(_ title: String, on: Bool, action: @escaping (Bool) -> Void) -> NSButton {
        let btn = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        btn.font = .systemFont(ofSize: 12)
        btn.state = on ? .on : .off
        let box = ActionBox { sender in
            action((sender as? NSButton)?.state == .on)
        }
        retained.append(box)
        btn.target = box
        btn.action = #selector(ActionBox.fire(_:))
        return btn
    }

    private func numberRow(_ title: String, value: Int, range: ClosedRange<Int>,
                           unit: String, enabled: Bool = true,
                           onChange: @escaping (Int) -> Void) -> NSView {
        let field = NSTextField(string: "\(value)")
        field.alignment = .right
        field.font = .systemFont(ofSize: 12)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 58).isActive = true

        let stepper = NSStepper()
        stepper.minValue = Double(range.lowerBound)
        stepper.maxValue = Double(range.upperBound)
        stepper.increment = 1
        stepper.integerValue = value

        let box = ActionBox { [weak field] sender in
            guard let field else { return }
            let raw = (sender as? NSStepper)?.integerValue ?? Int(field.stringValue) ?? value
            let v = min(max(raw, range.lowerBound), range.upperBound)
            stepper.integerValue = v
            field.stringValue = "\(v)"
            onChange(v)
        }
        retained.append(box)
        stepper.target = box
        stepper.action = #selector(ActionBox.fire(_:))
        field.target = box
        field.action = #selector(ActionBox.fire(_:))
        field.isEnabled = enabled
        stepper.isEnabled = enabled
        field.textColor = enabled ? .labelColor : .tertiaryLabelColor

        var views: [NSView] = [field, stepper]
        if !unit.isEmpty { views.append(sxLabel(unit, size: 11, color: .secondaryLabelColor)) }
        return row(title, sxHStack(views, spacing: 6))
    }

    private func popupRow(_ title: String, items: [String], selected: Int,
                          onChange: @escaping (Int) -> Void) -> NSView {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: items)
        popup.selectItem(at: min(max(selected, 0), max(items.count - 1, 0)))
        popup.font = .systemFont(ofSize: 12)
        popup.bezelStyle = .rounded
        popup.controlSize = .regular
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.widthAnchor.constraint(equalToConstant: 190).isActive = true

        let box = ActionBox { sender in
            guard let p = sender as? NSPopUpButton else { return }
            onChange(p.indexOfSelectedItem)
        }
        retained.append(box)
        popup.target = box
        popup.action = #selector(ActionBox.fire(_:))
        return row(title, popup)
    }

    private func plainButton(_ title: String, _ action: @escaping () -> Void) -> NSButton {
        let btn = NSButton(title: title, target: nil, action: nil)
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        btn.font = .systemFont(ofSize: 12)
        let box = ActionBox { _ in action() }
        retained.append(box)
        btn.target = box
        btn.action = #selector(ActionBox.fire(_:))
        return btn
    }

    /// 一组设置装进竖直堆叠，行间距统一
    private func group(_ views: [NSView], spacing: CGFloat = 8) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = spacing
        return s
    }

    // MARK: - 行式页面（标题在左、控件紧跟，整行撑满内容区）

    /// 把若干行竖着排成一张页面：每行左右都贴住页面，宽度天然一致
    private func pane(_ rows: [NSView], gap: CGFloat = 10) -> NSView {
        let box = FlippedView()
        var last: NSView?
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(row)
            row.leadingAnchor.constraint(equalTo: box.leadingAnchor).isActive = true
            row.trailingAnchor.constraint(equalTo: box.trailingAnchor).isActive = true
            if let last {
                row.topAnchor.constraint(equalTo: last.bottomAnchor, constant: gap).isActive = true
            } else {
                row.topAnchor.constraint(equalTo: box.topAnchor).isActive = true
            }
            last = row
        }
        last?.bottomAnchor.constraint(equalTo: box.bottomAnchor).isActive = true
        return box
    }

    /// 行间留白
    private func gapRow(_ h: CGFloat) -> NSView {
        let v = NSView()
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        return v
    }

    /// 复选框行：整行可点，文字贴左
    private func toggleRow(_ title: String, on: Bool, action: @escaping (Bool) -> Void) -> NSView {
        let box = checkbox(title, on: on, action: action)
        box.alignment = .left
        box.heightAnchor.constraint(greaterThanOrEqualToConstant: 22).isActive = true
        return box
    }

    /// 按钮行：靠左排，不拉满
    private func buttonRow(_ buttons: [NSView]) -> NSView {
        sxHStack(buttons + [sxSpacer()], spacing: 8)
    }

    /// 说明行：按页面宽度折行
    private func noteRow(_ text: String) -> NSView {
        hint(text)
    }

    // MARK: - 各页

    private func generalPane() -> NSView {
        let login = toggleRow(Str.launchAtLogin, on: config.launchAtLogin ?? launchAtLoginEnabled()) { [weak self] on in
            self?.setLaunchAtLogin(on)
        }

        // 语言：选项一律用各自母语书写（不含日语）
        let langs = AppLang.allCases
        let current = AppLang.from(config.language) ?? L10n.lang
        let langPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        langPopup.addItems(withTitles: langs.map { $0.nativeName })
        langPopup.selectItem(at: langs.firstIndex(of: current) ?? 0)
        langPopup.font = .systemFont(ofSize: 12)
        langPopup.bezelStyle = .rounded
        langPopup.translatesAutoresizingMaskIntoConstraints = false
        langPopup.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let langBox = ActionBox { [weak self] sender in
            guard let p = sender as? NSPopUpButton else { return }
            let i = min(max(p.indexOfSelectedItem, 0), langs.count - 1)
            self?.update { $0.language = langs[i].rawValue }
        }
        retained.append(langBox)
        langPopup.target = langBox
        langPopup.action = #selector(ActionBox.fire(_:))

        // 面板外观（原在「状态面板」页）
        let backgrounds = [Str.bgBlur, Str.bgWhite]
        let bgIndex = (config.panelBackground == "white") ? 1 : 0
        let bg = popupRow(Str.background, items: backgrounds, selected: bgIndex) { [weak self] i in
            self?.update { $0.panelBackground = i == 1 ? "white" : "popover" }
        }
        let width = numberRow(Str.panelWidth, value: Int(config.panelWidth ?? 340), range: 320...420, unit: "pt") { [weak self] v in
            self?.update { $0.panelWidth = Double(v) }
        }

        // 关闭设置窗口时的动作（下拉选择）
        let closePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        closePopup.addItems(withTitles: [Str.closeMinimize, Str.closeQuit])
        closePopup.selectItem(at: (config.closeAction ?? "minimize") == "quit" ? 1 : 0)
        closePopup.font = .systemFont(ofSize: 12)
        closePopup.bezelStyle = .rounded
        closePopup.translatesAutoresizingMaskIntoConstraints = false
        closePopup.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let closeBox = ActionBox { [weak self] sender in
            guard let p = sender as? NSPopUpButton else { return }
            self?.update { $0.closeAction = p.indexOfSelectedItem == 1 ? "quit" : "minimize" }
        }
        retained.append(closeBox)
        closePopup.target = closeBox
        closePopup.action = #selector(ActionBox.fire(_:))

        return pane([
            sectionTitle(Str.secStartup),
            login,
            gapRow(12),
            sectionTitle(Str.secLanguage),
            row(Str.languageRow, langPopup),
            gapRow(12),
            sectionTitle(Str.secWindow),
            row(Str.closeAction, closePopup),
            gapRow(12),
            sectionTitle(Str.secAppearance),
            bg,
            width,
            gapRow(12),
            noteRow(Str.noteInstant)
        ])
    }

    private func widgetPane() -> NSView {
        let on = Set(config.metrics ?? MetricKind.allCases.map(\.rawValue))
        let avail = availability()

        var rows: [NSView] = [
            sectionTitle(Str.navWidget),
            hint(Str.noteMetrics)
        ]

        let row = PillRow()
        row.onToggle = { [weak self] kind, picked in self?.setEnabled(kind, picked) }
        row.onReorder = { [weak self] kinds in self?.setOrder(kinds) }
        row.items = orderedKinds().map { kind in
            let usable = avail[kind] ?? true
            return PillRow.Item(kind: kind, title: BarStrip.bandLabel(kind),
                                on: usable && on.contains(kind.rawValue), enabled: usable)
        }
        row.reload()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 24).isActive = true
        rows.append(row)

        for kind in MetricKind.allCases where !(avail[kind] ?? true) {
            rows.append(hint("\(BarStrip.bandLabel(kind)): \(Self.unavailableNote(kind))"))
        }

        rows.append(gapRow(8))
        let valuesPill = pill(Str.showValues, on: config.metricValues ?? true, enabled: true) { [weak self] picked in
            self?.update { $0.metricValues = picked }
        }
        let autoPill = pill(Str.autoWidth, on: config.autoWidth ?? true, enabled: true) { [weak self] picked in
            self?.update { $0.autoWidth = picked }
        }
        rows.append(sxHStack([valuesPill, autoPill, sxSpacer()], spacing: 6))
        rows.append(hint(Str.noteNet))
        rows.append(hint(Str.noteFan))
        return pane(rows)
    }

    /// 当前显示顺序（全部组件，含未启用）
    private func orderedKinds() -> [MetricKind] {
        let raw = config.metricOrder ?? MetricKind.allCases.map(\.rawValue)
        var seen = Set<MetricKind>()
        var out: [MetricKind] = []
        for id in raw {
            guard let k = MetricKind(rawValue: id), !seen.contains(k) else { continue }
            seen.insert(k); out.append(k)
        }
        out += MetricKind.allCases.filter { !seen.contains($0) }
        return out
    }

    /// 勾选/取消某个组件（保持当前顺序）
    private func setEnabled(_ kind: MetricKind, _ enabled: Bool) {
        update { cfg in
            let order = (cfg.metricOrder ?? MetricKind.allCases.map(\.rawValue))
            var set = Set(cfg.metrics ?? MetricKind.allCases.map(\.rawValue))
            if enabled { set.insert(kind.rawValue) } else { set.remove(kind.rawValue) }
            cfg.metricOrder = order
            cfg.metrics = order.filter { set.contains($0) }
        }
    }

    /// 拖动后的新顺序
    private func setOrder(_ kinds: [MetricKind]) {
        update { cfg in
            let order = kinds.map(\.rawValue)
            let set = Set(cfg.metrics ?? MetricKind.allCases.map(\.rawValue))
            cfg.metricOrder = order
            cfg.metrics = order.filter { set.contains($0) }
        }
    }

    /// 改当前编辑组件的显示配置，然后重建这一页（chips 要跟着变）
    private func editSettings(_ mutate: @escaping (inout MetricSettings) -> Void) {
        let kind = editingKind
        update { cfg in
            var s = cfg.settings(for: kind)
            mutate(&s)
            cfg.setSettings(s, for: kind)
        }
        show(page)
    }

    /// 「状态面板」左列：组件清单
    private func componentList() -> NSView {
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 1
        list.translatesAutoresizingMaskIntoConstraints = false
        list.widthAnchor.constraint(equalToConstant: 104).isActive = true
        // 跟「状态组件」里拖出来的顺序一致，别用枚举固定顺序
        for kind in orderedKinds() {
            let selected = kind == editingKind
            let b = NSButton(title: Self.metricLabel(kind), target: nil, action: nil)
            b.isBordered = false
            b.font = .systemFont(ofSize: 12, weight: selected ? .semibold : .regular)
            b.contentTintColor = selected ? .controlAccentColor : .labelColor
            b.alignment = .left
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 24).isActive = true
            let box = ActionBox { [weak self] _ in
                guard let self else { return }
                self.editingKind = kind
                self.show(.panel)
            }
            retained.append(box)
            b.target = box
            b.action = #selector(ActionBox.fire(_:))
            list.addArrangedSubview(b)
        }
        return list
    }

    /// 「状态面板」右侧的组件详情：显示开关 + 数值项编辑
    private func componentDetail(_ kind: MetricKind) -> NSView {
        let cfg = config.settings(for: kind)

        let iconPill = pill(Str.showIcon, on: cfg.showIcon, enabled: true) { [weak self] v in
            self?.editSettings { $0.showIcon = v }
        }
        let textPill = pill(Str.showText, on: cfg.showText, enabled: true) { [weak self] v in
            self?.editSettings { $0.showText = v }
        }
        let chartPill = pill(Str.showChart, on: cfg.showChart, enabled: true) { [weak self] v in
            self?.editSettings { $0.showChart = v }
        }

        let options = MetricCatalog.options(kind)
        let selected = ChipRow()
        selected.onRemove = { [weak self] id in
            self?.editSettings { $0.values.removeAll { $0 == id } }
        }
        selected.onReorder = { [weak self] ids in
            self?.editSettings { $0.values = ids }
        }
        selected.chips = cfg.values.enumerated().compactMap { index, id in
            options.first { $0.id == id }.map {
                ChipRow.Chip(id: id, title: "\(index + 1). \($0.label)")
            }
        }
        selected.translatesAutoresizingMaskIntoConstraints = false
        selected.heightAnchor.constraint(equalToConstant: 26).isActive = true

        var rows: [NSView] = [
            sxHStack([iconPill, textPill, chartPill, sxSpacer()], spacing: 6),
            hint(Str.noteValues),
            selected
        ]

        let rest = options.filter { !cfg.values.contains($0.id) }
        if !rest.isEmpty {
            rows.append(hint(Str.noteAvailable))
            let availRow = ChipRow()
            availRow.onTap = { [weak self] id in
                self?.editSettings {
                    guard !$0.values.contains(id) else { return }
                    if $0.values.count >= MetricCatalog.maxLines { $0.values.removeLast() }
                    $0.values.append(id)
                }
            }
            availRow.chips = rest.map { ChipRow.Chip(id: $0.id, title: $0.label) }
            availRow.translatesAutoresizingMaskIntoConstraints = false
            availRow.heightAnchor.constraint(equalToConstant: 26).isActive = true
            rows.append(availRow)
        }
        return group(rows, spacing: 8)
    }

    /// 胶囊按钮：选中 = 强调色实心；未选中 = 浅灰；禁用 = 更淡且不响应点击
    private func pill(_ title: String, on: Bool, enabled: Bool,
                      action: @escaping (Bool) -> Void) -> TogglePill {
        let p = TogglePill(title: title)
        p.state = on ? .on : .off
        p.isEnabled = enabled
        p.needsDisplay = true
        let box = ActionBox { sender in
            guard let btn = sender as? TogglePill, btn.isEnabled else { return }
            action(btn.state == .on)
            btn.needsDisplay = true
        }
        retained.append(box)
        p.target = box
        p.action = #selector(ActionBox.fire(_:))
        return p
    }

    /// 禁用原因（设置页里跟在胶囊后面）
    private static func unavailableNote(_ kind: MetricKind) -> String {
        switch kind {
        case .fan:     return Str.unavailableFan
        case .battery: return Str.unavailableBattery
        default:       return ""
        }
    }

    /// 组件名（界面文案）
    private static func metricLabel(_ kind: MetricKind) -> String {
        switch kind {
        case .cpu:     return Str.metricCPU
        case .gpu:     return Str.metricGPU
        case .memory:  return Str.metricMemory
        case .network: return Str.metricNetwork
        case .disk:    return Str.metricDisk
        case .battery: return Str.metricBattery
        case .fan:     return Str.metricFan
        }
    }

    private func panelPane() -> NSView {
        group([
            sectionTitle(Str.secComponents),
            hint(Str.noteComponentDetail),
            sxHStack([componentList(), componentDetail(editingKind), sxSpacer()], spacing: 18)
        ], spacing: 10)
    }

    private func aboutPane() -> NSView {
        let info = Bundle.main.infoDictionary
        let ver = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"

        let cfgDir = Config.dir.path
        let docs = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("docs").path

        return group([
            sxHStack([sxLabel("StatusX", size: 16, weight: .bold),
                      sxLabel("v\(ver) · \(Str.buildTag(build))", size: 11, color: .secondaryLabelColor)], spacing: 8),
            sxDivider(),
            row(Str.configFile, horizontalPathRow(cfgDir)),
            row(Str.runLog, horizontalLogRow()),
            row(Str.docs, horizontalPathRow(docs)),
            sxDivider(),
            plainButton(Str.quitApp) { NSApp.terminate(nil) }
        ], spacing: 12)
    }

    private func horizontalPathRow(_ path: String) -> NSView {
        let label = sxLabel(path, size: 11, color: .secondaryLabelColor)
        label.lineBreakMode = .byTruncatingMiddle
        label.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return sxHStack([label, plainButton(Str.open) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }], spacing: 8)
    }

    private func horizontalLogRow() -> NSView {
        sxHStack([sxLabel("/tmp/statusx.log", size: 11, color: .secondaryLabelColor),
                  plainButton(Str.open) {
                      NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp/statusx.log"))
                  }], spacing: 8)
    }

    // MARK: - 登录项

    private func launchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    private func setLaunchAtLogin(_ on: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            update { $0.launchAtLogin = on }
            Log.line("登录项 \(on ? "已注册" : "已移除")")
        } catch {
            // 从 build/ 目录直接跑二进制时通常注册失败，如实记录并回显真实状态
            Log.line("登录项设置失败：\(error.localizedDescription)")
            update { $0.launchAtLogin = SMAppService.mainApp.status == .enabled }
        }
        show(.general)
    }
}

extension SettingsWindowController: NSWindowDelegate {
    /// 关闭设置窗口：minimize = 只关窗，StatusX 继续守在菜单栏；quit = 直接退出 App
    func windowWillClose(_ notification: Notification) {
        guard (config.closeAction ?? "minimize") == "quit" else { return }
        guard !quittingFromClose else { return }
        quittingFromClose = true
        Log.line("关闭设置窗口 → 按配置退出 StatusX")
        NSApp.terminate(nil)
    }
}

/// 设置页里的胶囊开关：三种视觉状态——选中（强调色实心）、未选中（浅灰）、禁用（更淡、无响应）。
class TogglePill: NSButton {

    init(title: String) {
        super.init(frame: .zero)
        self.title = title
        setButtonType(.toggle)
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        font = .systemFont(ofSize: 11, weight: .medium)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("不支持 nib 加载") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: fittingWidth(), height: 22)
    }

    /// 胶囊宽度：文字宽 + 左右内边距
    func fittingWidth() -> CGFloat {
        let w = (title as NSString).size(withAttributes: [.font: font ?? .systemFont(ofSize: 11)]).width
        return ceil(w) + 18
    }

    override func draw(_ dirtyRect: NSRect) {
        let on = state == .on && isEnabled
        let radius = bounds.height / 2
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: radius, yRadius: radius)

        let fill: NSColor
        if !isEnabled {
            fill = NSColor.quaternaryLabelColor.withAlphaComponent(0.45)
        } else if on {
            fill = NSColor.controlAccentColor
        } else {
            fill = NSColor.quaternaryLabelColor
        }
        fill.setFill()
        path.fill()

        if isHighlighted && isEnabled {
            NSColor.black.withAlphaComponent(0.08).setFill()
            path.fill()
        }

        let color: NSColor = !isEnabled ? .tertiaryLabelColor : (on ? .white : .labelColor)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? .systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: color
        ]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                             y: (bounds.height - size.height) / 2),
                                 withAttributes: attrs)
    }
}
