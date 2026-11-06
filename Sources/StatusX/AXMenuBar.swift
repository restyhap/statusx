import Cocoa
import ApplicationServices

/// 菜单栏里的一项（别人的或自己的）
struct MBItem {
    let appName: String
    let bundleID: String
    let pid: pid_t
    let element: AXUIElement
    let frame: CGRect
    let actions: [String]

    var isSystemBar: Bool { appName == "MenuBarAgent" }
}

enum MBar {

    /// 系统代理（输入法、控制中心等）：它们也有状态项，但不是用户要"显示的应用"
    static let systemAgentBundleIDs: Set<String> = [
        "com.apple.TextInputMenuAgent", "com.apple.TextInputSwitcher",
        "com.apple.controlcenter", "com.apple.MenuBarAgent",
        "com.apple.WindowManager", "com.apple.SystemUIServer",
        "com.apple.dock", "com.apple.notificationcenterui",
        "com.apple.spotlight", "com.apple.WiFiAgent"
    ]

    static func trusted() -> Bool { AXIsProcessTrusted() }

    /// 缓存的"有菜单栏项"的 App 清单，避免每次全量枚举
    private static var knownPids: [pid_t] = []
    /// 上一次扫描到的完整结果（点击弹窗时直接复用）
    private static var cache: [MBItem] = []
    /// 已经扫过的 pid（含"扫过但没有菜单栏项"的 App）。
    /// 少了它，每次点击都会把没项儿的 App 当"新开的"重扫一遍。
    private static var scannedPids: Set<pid_t> = []
    /// 最近一次扫描到的 bundle id（图标预热用）
    private static var knownBIDs: [String] = []
    /// 扫描可能发生在后台队列，这两个缓存要加锁
    private static let stateLock = NSLock()

    static func knownBundleIDs() -> [String] {
        stateLock.lock(); defer { stateLock.unlock() }
        return knownBIDs
    }

    private static func remember(_ items: [MBItem]) {
        stateLock.lock()
        cache = items
        knownPids = Array(Set(items.map { $0.pid }))
        knownBIDs = Array(Set(items.map { $0.bundleID }))
        stateLock.unlock()
    }

    /// 点击弹窗用的快速刷新：只拿"运行中的 App 集合"做差集。
    /// 已退出的项丢掉、新出现的 App 才扫（通常 0~1 个），其余直接复用缓存。
    static func refreshCached() -> [MBItem] {
        stateLock.lock()
        let cached = cache
        let scanned = scannedPids
        stateLock.unlock()
        guard !cached.isEmpty else { return scanAllFast() }

        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
        let alivePids = Set(running.map { $0.processIdentifier })
        var merged = cached.filter { alivePids.contains($0.pid) }

        let fresh = running
            .filter { !scanned.contains($0.processIdentifier) }
            .map { (pid: $0.processIdentifier, name: $0.localizedName ?? "?", bid: $0.bundleIdentifier ?? "") }

        if !fresh.isEmpty {
            merged.append(contentsOf: scanApps(fresh, timeout: 0.25))
            stateLock.lock()
            scannedPids = scanned.intersection(alivePids).union(fresh.map { $0.pid })
            stateLock.unlock()
        }

        let out = merged.sorted { $0.frame.origin.x < $1.frame.origin.x }
        remember(out)
        return out
    }

    static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    static func frame(_ el: AXUIElement) -> CGRect {
        var p = CGPoint.zero
        var s = CGSize.zero
        if let v = attr(el, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() {
            _ = AXValueGetValue(v as! AXValue, .cgPoint, &p)
        }
        if let v = attr(el, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() {
            _ = AXValueGetValue(v as! AXValue, .cgSize, &s)
        }
        return CGRect(origin: p, size: s)
    }

    static func actions(_ el: AXUIElement) -> [String] {
        var arr: CFArray?
        AXUIElementCopyActionNames(el, &arr)
        return (arr as? [String]) ?? []
    }

    private static func items(of app: NSRunningApplication, withActions: Bool) -> [MBItem] {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        // 个别 App 的 AX 会无响应，把单次调用超时压到 0.4s
        AXUIElementSetMessagingTimeout(root, 0.4)
        guard let barRef = attr(root, kAXExtrasMenuBarAttribute) else { return [] }
        let bar = barRef as! AXUIElement
        AXUIElementSetMessagingTimeout(bar, 0.4)
        guard let kids = attr(bar, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        return kids.map { k in
            MBItem(appName: app.localizedName ?? "?",
                   bundleID: app.bundleIdentifier ?? "",
                   pid: app.processIdentifier,
                   element: k,
                   frame: frame(k),
                   actions: withActions ? actions(k) : [])
        }
    }

    /// 全量枚举（启动时用一次）
    @discardableResult
    static func scanAll(withActions: Bool = false) -> [MBItem] {        var out: [MBItem] = []
        var pids: [pid_t] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy != .prohibited else { continue }
            let got = items(of: app, withActions: withActions)
            if !got.isEmpty {
                out.append(contentsOf: got)
                pids.append(app.processIdentifier)
            }
        }
        stateLock.lock(); knownPids = pids; stateLock.unlock()
        return out.sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    /// 并行全量扫描：一个 App 一个线程。
    /// 串行时每个不响应的 App 都会耗掉一次超时，总耗时是它们的**和**（实测 2.9s）；
    /// 并行后总耗时约等于最慢的那一个（0.25s 上限）。
    @discardableResult
    static func scanAllFast() -> [MBItem] {
        // 先把 NSRunningApplication 读成值类型快照，再进并发
        let snaps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .map { (pid: $0.processIdentifier, name: $0.localizedName ?? "?", bid: $0.bundleIdentifier ?? "") }
        guard !snaps.isEmpty else { return [] }

        let all = scanApps(snaps, timeout: 0.25).sorted { $0.frame.origin.x < $1.frame.origin.x }
        stateLock.lock(); scannedPids = Set(snaps.map { $0.pid }); stateLock.unlock()
        remember(all)
        return all
    }

    /// 并行扫描给定的一批 App（一个 App 一个线程）
    private static func scanApps(_ snaps: [(pid: pid_t, name: String, bid: String)],
                                 timeout: Float) -> [MBItem] {
        var perApp = [[MBItem]](repeating: [], count: snaps.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: snaps.count) { i in
            let s = snaps[i]
            let got = items(pid: s.pid, name: s.name, bundleID: s.bid, timeout: timeout)
            // AXUIElement 是 CF 类型，可跨线程持有；数组写入用锁保护
            lock.lock()
            perApp[i] = got
            lock.unlock()
        }
        return perApp.flatMap { $0 }
    }

    /// 按 pid 取状态栏项（供并行扫描调用，超时同时压到子元素上）
    private static func items(pid: pid_t, name: String, bundleID: String,
                              timeout: Float, withActions: Bool = false) -> [MBItem] {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, timeout)
        guard let barRef = attr(root, kAXExtrasMenuBarAttribute) else { return [] }
        let bar = barRef as! AXUIElement
        AXUIElementSetMessagingTimeout(bar, timeout)
        guard let kids = attr(bar, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        // 子元素也要设超时，否则 frame()/actions() 会退回 6 秒默认值
        for k in kids { AXUIElementSetMessagingTimeout(k, timeout) }
        return kids.map { k in
            MBItem(appName: name,
                   bundleID: bundleID,
                   pid: pid,
                   element: k,
                   frame: frame(k),
                   actions: withActions ? actions(k) : [])
        }
    }

    /// 只扫已知有项的 App（启动后常用，快）
    @discardableResult
    static func scanKnown(withActions: Bool = false) -> [MBItem] {
        stateLock.lock(); let pids = knownPids; stateLock.unlock()
        guard !pids.isEmpty else { return scanAll(withActions: withActions) }
        var out: [MBItem] = []
        var alive: [pid_t] = []
        for pid in pids {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy != .prohibited else { continue }
            let got = items(of: app, withActions: withActions)
            if !got.isEmpty { out.append(contentsOf: got); alive.append(pid) }
        }
        stateLock.lock(); knownPids = alive; stateLock.unlock()
        return out.sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    /// 定向枚举（校验时用，快一个数量级）
    static func scan(pids: [pid_t], withActions: Bool = false) -> [MBItem] {
        var out: [MBItem] = []
        for pid in pids {
            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
            out.append(contentsOf: items(of: app, withActions: withActions))
        }
        return out.sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    /// 只读自己（最快）
    static func own() -> MBItem? {
        scan(pids: [getpid()]).first
    }

    /// 系统条缓存：`overflow()` / `zoneRight()` / `isSelfFolded()` 一轮里会问好几次，
    /// 每次重新扫一遍要 30–70ms，这里 250ms 内复用同一份
    private static var sysCache: ([MBItem], CFAbsoluteTime) = ([], 0)

    static func systemBarCached() -> [MBItem] {
        stateLock.lock()
        let (cached, at) = sysCache
        stateLock.unlock()
        if !cached.isEmpty, CFAbsoluteTimeGetCurrent() - at < 0.25 { return cached }
        let fresh = systemBar()
        stateLock.lock(); sysCache = (fresh, CFAbsoluteTimeGetCurrent()); stateLock.unlock()
        return fresh
    }

    /// 定向快照：只扫给定 bundle 对应的运行中 App（并行）。
    /// 实测全量并行扫描 520ms（被几个不响应的 Electron 进程拖到超时），定向 4 个 App 只要 2ms。
    static func snapshot(bundleIDs: [String], timeout: Float = 0.15) -> [MBItem] {
        var seen = Set<String>()
        let wanted = bundleIDs.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !wanted.isEmpty else { return [] }
        var byBID: [String: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy != .prohibited {
            if let b = app.bundleIdentifier, wanted.contains(b), byBID[b] == nil { byBID[b] = app }
        }
        let snaps: [(pid: pid_t, name: String, bid: String)] = wanted.compactMap { bid in
            guard let app = byBID[bid] else { return nil }
            return (app.processIdentifier, app.localizedName ?? "?", bid)
        }
        guard !snaps.isEmpty else { return [] }
        return scanApps(snaps, timeout: timeout).sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    /// 只读系统条（控制中心 / 时钟 / 折叠按钮）
    static func systemBar() -> [MBItem] {
        guard let agent = NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.apple.MenuBarAgent" || $0.localizedName == "MenuBarAgent" })
        else { return [] }
        return items(of: agent, withActions: false)
    }

    /// 折叠按钮 `<<`
    static func overflow() -> MBItem? {
        systemBarCached().first { $0.frame.width < 20 && $0.frame.height > 30 }
    }

    /// 应用区右边界（控制中心左边 12px）
    /// 注意：`<<` 按钮本身也是 MenuBarAgent 项（宽 17px），必须取最右的那个才算控制中心
    static func zoneRight() -> CGFloat {
        let sys = systemBarCached()
        let cc = sys.filter { $0.frame.width > 6 && $0.frame.width < 60 }
            .map { $0.frame.origin.x }.max()
        let edge = (cc ?? screenWidth - 16) - 12
        // 健全性检查：右边界不可能落在屏幕左半边
        return edge > screenWidth * 0.6 ? edge : screenWidth - 16
    }

    /// 状态项在窗口服务器里是 layer=25 的窗口，窗口列表给出**真实渲染宽度**。
    /// AX 的 width 会是脏值（实测 Blip 报 20 / 真实 24，微信报 20 / 真实 32），
    /// 而窗口边界不需要屏幕录制权限、也不受 AX 缓存影响（2026-10-27 实测）。
    static func statusWindowWidths() -> [pid_t: [CGFloat]] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var out: [pid_t: [CGFloat]] = [:]
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 25,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = b["Width"], let y = b["Y"], y < 40, width > 4, width < 400
            else { continue }
            out[pid, default: []].append(width)
        }
        return out
    }

    static func press(_ el: AXUIElement) -> AXError {
        AXUIElementPerformAction(el, kAXPressAction as CFString)
    }

    static var screenWidth: CGFloat { NSScreen.main?.frame.width ?? 0 }
    static func screenRightEdge() -> CGFloat { screenWidth }
}
