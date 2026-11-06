import Cocoa

/// StatusX 在菜单栏里就是一条 310px 的带子：只画启用的系统指标（CPU / 内存 / 网络 / 硬盘 / 电池 / 风扇），
/// 不再画自己的标识——整条都可以点开面板。
/// 每个指标 = 大图标 + 右侧两行文字（上：数值，下：名称）。
enum BarStrip {

    /// 带子左右留白
    static let edgePad: CGFloat = 3
    /// 自适应宽度时的下限（全关也要留一块能点的区域）
    static let minWidth: CGFloat = 44
    static let height: CGFloat = 22
    /// 画布高度 = 状态项高度。**不能比状态项高**：状态项按钮会把超出的部分裁掉，
    /// 之前把画布加高 1.5pt 再下移，结果名称被裁掉一条（2026-10-30 实测）
    static let imageHeight: CGFloat = height
    /// 每个图标都有一个正方形槽：图标在槽里上下左右都居中，文字位置由这个正方形决定。
    /// 这样"宽扁"的电池和"方形"的 CPU 在视觉上才是同一个节奏（2026-10-30 定案）
    static let iconBoxSide: CGFloat = 11.5
    /// 图标统一墨迹高度：不同图标自带留白差别很大，按「墨迹高度」对齐视觉大小
    /// （实测各图标墨迹 bbox 占画布 0.59–0.93，等高对齐后大小才一致）
    static let iconInkHeight: CGFloat = 10
    /// 单个图标允许的最大墨迹宽度：电池这类横长图标不能无限撑宽
    static let iconInkMaxWidth: CGFloat = 15
    /// 只有图标、没有名称时用的边长（目前没用到，留着给以后的纯图标模式）
    static let iconSide: CGFloat = 16
    /// 指标之间的间距（放不下时依次降到 5 / 4）
    static let gaps: [CGFloat] = [5, 4, 3]
    /// 左列（图标+名称）与右侧数值之间的距离
    static let valueGap: CGFloat = 4.5
    /// 图标方槽与名称之间的竖向间隔
    static let iconLabelGap: CGFloat = 0.8

    static let valueSize: CGFloat = 10
    static let labelSize: CGFloat = 7

    /// 载入后的图标：原图 + 图形墨迹在原图里的相对矩形
    struct LoadedIcon {
        let image: NSImage
        /// 墨迹包围盒（单位坐标 0…1，原点左下）
        let ink: NSRect
        /// 墨迹重心（单位坐标 0…1，原点左下）——上下居中按它算，才算「看起来居中」
        let mass: NSPoint
    }

    private static var iconCache: [String: LoadedIcon] = [:]

    /// 菜单栏这会儿是深是浅：系统按壁纸取色，所以直接量壁纸顶部那条的平均亮度。
    /// 不能用状态项按钮的 effectiveAppearance——它会在挪位/变宽过程中来回跳（2026-10-26 实测）。
    private static var darkCache: (value: Bool, at: TimeInterval)?

    static func barIsDark() -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        if let c = darkCache, now - c.at < 20 { return c.value }
        let v = computeDark()
        darkCache = (v, now)
        return v
    }

    static func resetDarkCache() {
        darkCache = nil
    }

    private static func computeDark() -> Bool {
        guard let screen = NSScreen.screens.first,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        let h = max(1, Int(Double(cg.height) * 0.03))
        guard let strip = cg.cropping(to: CGRect(x: 0, y: 0, width: cg.width, height: h)) else {
            return false
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8,
                                  bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        ctx.interpolationQuality = .medium
        ctx.draw(strip, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let luma = (0.299 * Double(pixel[0]) + 0.587 * Double(pixel[1]) + 0.114 * Double(pixel[2])) / 255
        return luma < 0.6
    }

    /// 载入随包发布的 SVG 图标，并按菜单栏明暗染色。
    ///
    /// `isTemplate = true` 对 `_NSSVGImageRep` 不生效（实测：设为模板图后仍按 SVG 里的颜色画），
    /// 所以这里直接把 SVG 文本里的 `currentColor` 换成目标色再解析，解析结果按「图标+明暗」缓存。
    static func icon(_ name: String, dark: Bool) -> LoadedIcon? {
        let key = name + (dark ? "-light" : "-dark")
        if let cached = iconCache[key] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "assets"),
              var text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let hex = dark ? "#ffffff" : "#000000"
        // 只替换描边/填充属性的颜色值，`fill="none"` 必须保留（整条路径就靠它保持空心）
        if let re = try? NSRegularExpression(
            pattern: "(stroke|fill|color)=\"(#[0-9a-fA-F]{3,8}|currentColor|black|white)\"") {
            let full = NSRange(text.startIndex..., in: text)
            text = re.stringByReplacingMatches(in: text, range: full, withTemplate: "$1=\"\(hex)\"")
        }
        guard let data = text.data(using: .utf8), let img = NSImage(data: data) else { return nil }
        let metrics = inkRect(of: img)
        let loaded = LoadedIcon(image: img, ink: metrics.rect, mass: metrics.mass)
        iconCache[key] = loaded
        return loaded
    }

    /// 量出图标里「真正有墨」的那块区域（0…1 相对坐标）。
    /// 各套图标自带留白不一样（arcticons 留白多、andrsrxn 顶到边），不归一化就会一个显大一个显小。
    private static func inkRect(of img: NSImage) -> (rect: NSRect, mass: NSPoint) {
        let n = 64
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            return (NSRect(x: 0, y: 0, width: 1, height: 1), NSPoint(x: 0.5, y: 0.5))
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        img.draw(in: NSRect(x: 0, y: 0, width: CGFloat(n), height: CGFloat(n)))
        NSGraphicsContext.restoreGraphicsState()

        var minX = n, minY = n, maxX = -1, maxY = -1
        var sumX = 0.0, sumY = 0.0, sumA = 0.0
        for y in 0..<n {
            for x in 0..<n {
                let a = Double(rep.colorAt(x: x, y: y)?.alphaComponent ?? 0)
                guard a > 0.12 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                sumX += Double(x) * a
                sumY += Double(y) * a
                sumA += a
            }
        }
        guard maxX >= 0, sumA > 0 else {
            return (NSRect(x: 0, y: 0, width: 1, height: 1), NSPoint(x: 0.5, y: 0.5))
        }
        // 位图扫描的 y 是自顶向下，翻成 NSImage 的左下原点
        let rect = NSRect(x: CGFloat(minX) / CGFloat(n),
                          y: 1 - CGFloat(maxY + 1) / CGFloat(n),
                          width: CGFloat(maxX - minX + 1) / CGFloat(n),
                          height: CGFloat(maxY - minY + 1) / CGFloat(n))
        let mass = NSPoint(x: sumX / sumA / Double(n), y: 1 - sumY / sumA / Double(n))
        return (rect, mass)
    }

    /// 按墨迹矩形等比缩放到目标框里，保证各图标视觉大小一致
    /// 名称离带子下缘的距离
    private static let labelBottom: CGFloat = 0

    private static var boltCache: [String: NSImage] = [:]

    /// 充电闪电标识（SF Symbol 上色后缓存）
    private static func boltImage(dark: Bool, alpha: CGFloat) -> NSImage? {
        let key = "\(dark ? "light" : "dark")-\(Int(alpha * 100))"
        if let cached = boltCache[key] { return cached }
        let conf = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
            .applying(.init(paletteColors: [(dark ? NSColor.white : NSColor.black).withAlphaComponent(alpha)]))
        guard let img = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "charging")?
            .withSymbolConfiguration(conf) else { return nil }
        boltCache[key] = img
        return img
    }

    /// 个别图标的视觉校正：同样是 10pt 墨迹高，CPU 这种方形细笔画看起来更小，单独放大
    private static let opticalHeight: [String: CGFloat] = ["cpu": 11.2]

    /// 这个图标画出来有多大：墨迹高度固定，宽度按比例，超过上限再压回
    static func iconSize(_ ic: LoadedIcon, name: String = "", maxHeight: CGFloat = .greatestFiniteMagnitude) -> NSSize {
        let size = ic.image.size
        let inkW = ic.ink.width * size.width
        let inkH = ic.ink.height * size.height
        let target = min(opticalHeight[name] ?? iconInkHeight, maxHeight)
        guard inkW > 0, inkH > 0 else { return NSSize(width: target, height: target) }
        var scale = target / inkH
        if inkW * scale > iconInkMaxWidth { scale = iconInkMaxWidth / inkW }
        return NSSize(width: (inkW * scale * 10).rounded() / 10,
                      height: (inkH * scale * 10).rounded() / 10)
    }

    /// 按墨迹矩形铺满目标框（目标框已按 `iconSize` 算好，不会变形）
    private static func drawIcon(_ ic: LoadedIcon, in rect: NSRect) {
        let size = ic.image.size
        let src = NSRect(x: ic.ink.minX * size.width, y: ic.ink.minY * size.height,
                         width: ic.ink.width * size.width, height: ic.ink.height * size.height)
        guard src.width > 0, src.height > 0 else { return }
        ic.image.draw(in: rect, from: src, operation: .sourceOver, fraction: 1)
    }

    // MARK: - 数值格式

    static func percentText(_ v: Double) -> String {
        "\(Int((v * 100).rounded()))%"
    }

    /// 速率压成 3–4 个字符：1.2M / 320k / 48
    static func rateText(_ bytes: Double) -> String {
        if bytes >= 1_000_000 { return String(format: "%.1fM", bytes / 1_000_000) }
        if bytes >= 10_000 { return String(format: "%.0fk", bytes / 1_000) }
        if bytes >= 1_000 { return String(format: "%.1fk", bytes / 1_000) }
        return "\(Int(bytes))"
    }

    static func fanText(_ rpm: Double) -> String {
        if rpm >= 1000 { return String(format: "%.1fk", rpm / 1000) }
        return "\(Int(rpm.rounded()))"
    }

    /// 字节压成 3–5 个字符：12.4G / 1.8T / 640M
    static func bytesText(_ bytes: Double) -> String {
        if bytes >= 1_000_000_000_000 { return String(format: "%.1fT", bytes / 1_000_000_000_000) }
        if bytes >= 1_000_000_000 { return String(format: "%.1fG", bytes / 1_000_000_000) }
        return String(format: "%.0fM", bytes / 1_000_000)
    }

    /// 分钟 → 3:12
    static func timeText(_ minutes: Double?) -> String? {
        guard let m = minutes, m > 0 else { return nil }
        let h = Int(m) / 60, mi = Int(m) % 60
        return String(format: "%d:%02d", h, mi)
    }

    /// 单个数值项 → 显示字符串
    static func valueString(_ kind: MetricKind, _ id: String, _ s: MetricSnapshot) -> String? {
        switch (kind, id) {
        case (.cpu, "usage"):     return percentText(s.cpu)
        case (.cpu, "temp"):      return s.cpuTemp.map { "\(Int($0.rounded()))°" }
        case (.gpu, "usage"):     return percentText(s.gpu)
        case (.cpu, "load1"):     return String(format: "%.2f", s.load1)
        case (.cpu, "load5"):     return String(format: "%.2f", s.load5)
        case (.cpu, "load15"):    return String(format: "%.2f", s.load15)
        case (.memory, "used"):   return percentText(s.memory)
        case (.memory, "free"):   return bytesText(s.memFree)
        case (.memory, "total"):  return bytesText(s.memTotal)
        case (.network, "down"):  return s.netDown >= 1 ? "↓" + rateText(s.netDown) : nil
        case (.network, "up"):    return s.netUp >= 1 ? "↑" + rateText(s.netUp) : nil
        case (.disk, "usage"):    return percentText(s.disk)
        case (.disk, "free"):     return bytesText(s.diskFree)
        case (.disk, "total"):    return bytesText(s.diskTotal)
        case (.battery, "percent"):   return s.battery.map { "\($0.percent)%" }
        case (.battery, "remaining"): return timeText(s.batteryRemaining)
        case (.fan, "rpm"):           return (s.fan ?? 0) > 0 ? s.fan.map { fanText($0) } : nil
        default: return nil
        }
    }

    /// 右侧插槽：行内容 + 字号 + 迷你曲线的数据
    struct ValueSlot {
        var lines: [String]
        var fontSize: CGFloat
        var chart: [Double]?
        var chartHeight: CGFloat
    }

    /// 按组件配置生成插槽：勾了图表就最多 1 行文字（高度不够）
    static func valueSlot(_ kind: MetricKind, _ s: MetricSnapshot,
                          settings: [MetricKind: MetricSettings]) -> ValueSlot? {
        let cfg = settings[kind] ?? .defaults(kind)
        let chart = cfg.showChart ? (s.history[kind] ?? []) : nil
        var lines = cfg.showText ? cfg.values.compactMap { valueString(kind, $0, s) } : []
        if let _ = chart {
            lines = Array(lines.prefix(1))
            return ValueSlot(lines: lines, fontSize: 8, chart: chart,
                             chartHeight: lines.isEmpty ? 13 : 7)
        }
        guard !lines.isEmpty else { return nil }
        lines = Array(lines.prefix(MetricCatalog.maxLines))
        return ValueSlot(lines: lines, fontSize: lines.count > 1 ? 8.5 : valueSize,
                         chart: nil, chartHeight: 0)
    }

    private static func attributes(for size: CGFloat, dark: Bool) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium),
         .foregroundColor: dark ? NSColor.white : NSColor.black]
    }

    static func iconName(_ kind: MetricKind, _ s: MetricSnapshot) -> String {
        kind == .network ? s.netIcon : kind.iconName
    }

    private static func valueAttributes(dark: Bool) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: valueSize, weight: .medium),
         .foregroundColor: dark ? NSColor.white : NSColor.black]
    }

    private static func labelAttributes(dark: Bool) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: labelSize, weight: .regular),
         .foregroundColor: (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.78)]
    }

    /// 一个指标块：图标 + 两行文字里较宽的那行
    /// 所有组件的左列取同一宽度：图标列、名称列因此上下对齐，不会随「内存 / 硬盘」字数忽宽忽窄
    private static func uniformLeftWidth(_ kinds: [MetricKind], _ s: MetricSnapshot, dark: Bool) -> CGFloat {
        let widest = kinds.map { kind -> CGFloat in
            let labelW = ceil((bandLabel(kind) as NSString).size(withAttributes: labelAttributes(dark: dark)).width)
            return max(iconBoxSide, labelW)
        }.max() ?? 0
        return ceil(max(iconBoxSide, widest))
    }

    /// 某个组件当前图标的绘制宽度（网络会随接口换图标）
    private static func iconWidth(_ kind: MetricKind, _ s: MetricSnapshot, dark: Bool) -> CGFloat {
        let name = iconName(kind, s)
        guard let ic = icon(name, dark: dark) else { return iconInkHeight }
        return iconSize(ic, name: name).width
    }

    /// 图表固定宽度
    static let chartWidth: CGFloat = 18

    /// 组件宽度：统一的左列宽 + 间距 + 右侧数值
    private static func blockWidth(_ kind: MetricKind, _ s: MetricSnapshot,
                                   settings: [MetricKind: MetricSettings], dark: Bool, leftW: CGFloat) -> CGFloat {
        guard let slot = valueSlot(kind, s, settings: settings) else { return leftW }
        let attrs = attributes(for: slot.fontSize, dark: dark)
        var vw = slot.lines.map { ceil(($0 as NSString).size(withAttributes: attrs).width) }.max() ?? 0
        if slot.chart != nil { vw = max(vw, chartWidth) }
        return leftW + valueGap + vw
    }

    private static func valueWidth(_ value: String, dark: Bool) -> CGFloat? {
        ceil((value as NSString).size(withAttributes: valueAttributes(dark: dark)).width)
    }

    /// 带子里的短名称（两行文字的第二行）
    static func bandLabel(_ kind: MetricKind) -> String {
        switch kind {
        case .cpu:     return Str.bandCPU
        case .gpu:     return Str.bandGPU
        case .memory:  return Str.bandMemory
        case .network: return Str.bandNetwork
        case .disk:    return Str.bandDisk
        case .battery: return Str.bandBattery
        case .fan:     return Str.bandFan
        }
    }

    private static func visibleKinds(_ items: [MetricKind], _ s: MetricSnapshot) -> [MetricKind] {
        // 读不到数据的组件不画：判断用 `s.available`（与设置页那份完全一致），
        // 再兜一层「这一轮确实有值」，避免设置里禁用了、栏上还在显示（2026-10-30 实测踩到）
        items.filter { kind in
            guard s.available[kind] ?? true else { return false }
            switch kind {
            case .battery: return s.battery != nil
            case .fan:     return (s.fan ?? 0) > 0
            default:       return true
            }
        }
    }

    /// 每个数值项「最宽可能值」的占位文本
    private static func reserveText(_ kind: MetricKind, _ id: String) -> String {
        switch (kind, id) {
        case (.cpu, "usage"), (.gpu, "usage"), (.memory, "used"), (.disk, "usage"), (.battery, "percent"): return "100%"
        case (.cpu, "temp"): return "99°"
        case (.cpu, "load1"), (.cpu, "load5"), (.cpu, "load15"): return "99.99"
        case (.memory, "free"), (.memory, "total"), (.disk, "free"), (.disk, "total"): return "999.9G"
        case (.network, "down"), (.network, "up"): return "↓99.9M"
        case (.battery, "remaining"): return "99:59"
        case (.fan, "rpm"): return "9.9k"
        default: return "999"
        }
    }

    /// 按「最宽可能内容」预留宽度，和当前数值无关
    static func reserveWidth(metrics s: MetricSnapshot, items: [MetricKind],
                             settings: [MetricKind: MetricSettings], dark: Bool) -> CGFloat {
        let kinds = items.filter { s.available[$0] ?? true }
        guard !kinds.isEmpty else { return minWidth }
        let leftW = uniformLeftWidth(kinds, s, dark: dark)
        var blocks: [CGFloat] = []
        for kind in kinds {
            let cfg = settings[kind] ?? .defaults(kind)
            guard cfg.showText, !cfg.values.isEmpty else { blocks.append(leftW); continue }
            let texts = cfg.values.prefix(cfg.showChart ? 1 : MetricCatalog.maxLines).map { reserveText(kind, $0) }
            let size = cfg.showChart ? 8 : (cfg.values.count > 1 ? 8.5 : valueSize)
            let attrs = attributes(for: size, dark: dark)
            var w = texts.map { ceil(($0 as NSString).size(withAttributes: attrs).width) }.max() ?? 0
            if cfg.showChart { w = max(w, chartWidth) }
            blocks.append(leftW + valueGap + w)
        }
        return ceil(edgePad * 2 + blocks.reduce(0, +) + gaps[0] * CGFloat(max(0, blocks.count - 1)))
    }

    /// 内容总宽（不含状态项里剩余的空白）
    static func contentWidth(metrics s: MetricSnapshot, items: [MetricKind],
                             settings: [MetricKind: MetricSettings], dark: Bool = true) -> CGFloat {
        let kinds = visibleKinds(items, s)
        let leftW = uniformLeftWidth(kinds, s, dark: dark)
        let blocks = kinds.map { blockWidth($0, s, settings: settings, dark: dark, leftW: leftW) }
        return ceil(edgePad * 2 + blocks.reduce(0, +) + gaps[0] * CGFloat(max(0, blocks.count - 1)))
    }

    // MARK: - 画带子

    static func make(dark: Bool, metrics s: MetricSnapshot,
                     items: [MetricKind], settings: [MetricKind: MetricSettings],
                     maxWidth: CGFloat, fillWidth: Bool = false) -> NSImage {
        let dark0 = dark
        var kinds = visibleKinds(items, s)
        let leftW = uniformLeftWidth(kinds, s, dark: dark0)
        var blocks = kinds.map { blockWidth($0, s, settings: settings, dark: dark0, leftW: leftW) }

        // 先找能放下的最小间距；还放不下就从末尾裁组件（310 是硬上限）
        func total(_ gap: CGFloat) -> CGFloat {
            edgePad * 2 + blocks.reduce(0, +) + gap * CGFloat(max(0, blocks.count - 1))
        }
        var gap = gaps[0]
        for g in gaps where total(g) <= maxWidth {
            gap = g
            break
        }
        if total(gap) > maxWidth {
            gap = gaps.last ?? 4
            while total(gap) > maxWidth, !kinds.isEmpty {
                kinds.removeLast()
                blocks.removeLast()
            }
        }

        // 等宽格子：不论几个组件，中心点间距恒定
        var startX = edgePad
        var cellW: CGFloat = 0
        var useCells = false
        if fillWidth, !kinds.isEmpty {
            let usable = maxWidth - edgePad * 2
            let cw = usable / CGFloat(kinds.count)
            if (blocks.max() ?? 0) <= cw - 1 {
                useCells = true
                cellW = cw
            }
        }
        if fillWidth, !useCells, kinds.count > 1 {
            let contentW = edgePad * 2 + blocks.reduce(0, +)
            if maxWidth > contentW {
                let n = CGFloat(kinds.count - 1)
                gap = max(gaps[0], min((maxWidth - contentW) / n, 56))
                startX = edgePad + max(0, (maxWidth - (contentW + gap * n)) / 2)
            }
        }

        let width = fillWidth ? maxWidth : max(total(gap), iconSide + edgePad * 2)
        let h = imageHeight
        let labelAttrs = labelAttributes(dark: dark0)
        let tint: NSColor = dark0 ? .white : .black

        let image = NSImage(size: NSSize(width: width, height: h), flipped: false) { _ in
            var x = startX
            for (i, kind) in kinds.enumerated() {
                if useCells {
                    x = startX + CGFloat(i) * cellW + (cellW - blocks[i]) / 2
                } else if i > 0 {
                    x += gap
                }

                let cfg = settings[kind] ?? .defaults(kind)
                let lw = leftW

                // 左列：正方形图标槽在上、名称在下
                let labelH = ceil(labelAttrs[.font].map { ($0 as! NSFont).ascender - ($0 as! NSFont).descender } ?? 9)
                let name = iconName(kind, s)
                let boxY = labelBottom + labelH + iconLabelGap
                let boxRect = NSRect(x: x + (lw - iconBoxSide) / 2, y: boxY,
                                     width: iconBoxSide, height: iconBoxSide)
                let maxIconH = iconBoxSide - 0.5
                let loaded = icon(name, dark: dark0)
                let isz = loaded.map { iconSize($0, name: name, maxHeight: maxIconH) }
                    ?? NSSize(width: iconInkHeight, height: iconInkHeight)
                var iconRect = NSRect(x: boxRect.minX + (boxRect.width - isz.width) / 2,
                                      y: boxRect.minY + (boxRect.height - isz.height) / 2,
                                      width: isz.width, height: isz.height)
                if let loaded {
                    let cy = iconRect.minY + (loaded.mass.y - loaded.ink.minY) / loaded.ink.height * iconRect.height
                    iconRect.origin.y += max(-0.6, min(0.6, boxRect.midY - cy))
                }
                if ProcessInfo.processInfo.environment["STATUSX_DEBUG_ICONBOX"] == "1" {
                    tint.withAlphaComponent(0.5).setStroke()
                    NSBezierPath(rect: boxRect).stroke()
                }
                if cfg.showIcon {
                    if kind == .battery, let b = s.battery {
                        drawBattery(percent: b.percent, charging: b.charging, onAC: b.onAC,
                                    in: iconRect, tint: tint, dark: dark0)
                    } else if let ic = icon(name, dark: dark0) {
                        drawIcon(ic, in: iconRect)
                    }
                }

                let label = bandLabel(kind) as NSString
                let ls = label.size(withAttributes: labelAttrs)
                label.draw(at: NSPoint(x: x + (lw - ls.width) / 2, y: labelBottom),
                           withAttributes: labelAttrs)

                // 右列插槽：图表在上、文字在下；文字 1~2 行，每行在插槽里左右居中
                if let slot = valueSlot(kind, s, settings: settings) {
                    let attrs = attributes(for: slot.fontSize, dark: dark0)
                    let sizes = slot.lines.map { ($0 as NSString).size(withAttributes: attrs) }
                    let slotW = max(sizes.map { $0.width }.max() ?? 0,
                                    slot.chart == nil ? 0 : chartWidth)
                    let textH = sizes.reduce(0) { $0 + $1.height }
                    let chartH = slot.chartHeight
                    let contentH = textH + (slot.chart == nil ? 0 : chartH + 1)
                    var top = (h + contentH) / 2
                    if let data = slot.chart, data.count > 1 {
                        let rect = NSRect(x: x + lw + valueGap, y: top - chartH,
                                          width: slotW, height: chartH)
                        drawSparkline(data, in: rect, tint: tint)
                        top -= chartH + 1
                    }
                    // 第一项画在最上面：从顶往下排（y 是左下原点，所以先减行高再画）
                    var y = top
                    for (j, line) in slot.lines.enumerated() {
                        y -= sizes[j].height
                        let lineX = x + lw + valueGap + (slotW - sizes[j].width) / 2
                        (line as NSString).draw(at: NSPoint(x: lineX, y: y), withAttributes: attrs)
                    }
                }
                x += blocks[i]
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// 迷你曲线：右侧插槽里的一条折线（点按 0…1 高度铺开）
    private static func drawSparkline(_ data: [Double], in rect: NSRect, tint: NSColor) {
        guard data.count > 1 else { return }
        let path = NSBezierPath()
        path.lineWidth = 1
        path.lineJoinStyle = .round
        for (i, v) in data.enumerated() {
            let px = rect.minX + rect.width * CGFloat(i) / CGFloat(data.count - 1)
            let py = rect.minY + rect.height * CGFloat(min(1, max(0, v)))
            if i == 0 { path.move(to: NSPoint(x: px, y: py)) }
            else { path.line(to: NSPoint(x: px, y: py)) }
        }
        tint.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }

    /// 电池：先按电量画内部填充，再把电池外框图标盖上去。
    /// 「空白位置」= 从图标左内侧到内部宽度 × 百分比。
    private static func drawBattery(percent: Int, charging: Bool, onAC: Bool,
                                    in rect: NSRect, tint: NSColor, dark: Bool) {
        let pct = min(1, max(0, Double(percent) / 100))
        // 内腔相对图标框的近似内缩（电池图标自带一圈描边与外框）
        let insetX = rect.width * 0.16
        let insetY = rect.height * 0.30
        let inner = rect.insetBy(dx: insetX, dy: insetY)
        if pct > 0.02 {
            tint.setFill()
            let fill = NSRect(x: inner.minX, y: inner.minY,
                              width: inner.width * CGFloat(pct), height: inner.height)
            NSBezierPath(roundedRect: fill, xRadius: 1, yRadius: 1).fill()
        }
        if let ic = icon("battery", dark: dark) {
            drawIcon(ic, in: rect)
        }
        // 状态标识：充电 = 实心闪电；接电但未充电 = 半透明闪电；用电池 = 不画
        let boltAlpha: CGFloat = charging ? 1.0 : (onAC ? 0.38 : 0)
        if boltAlpha > 0, let bolt = boltImage(dark: dark, alpha: boltAlpha) {
            let side = min(6.5, rect.height * 0.7)
            bolt.draw(in: NSRect(x: rect.maxX - side * 0.55, y: rect.maxY - side * 0.85,
                                 width: side, height: side))
        }
    }
}

/// 图标带的承载视图：只负责显示，不抢点击（点击仍由状态项按钮处理）
final class StripHostView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
