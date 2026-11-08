import Cocoa
import IOKit.ps
import Network
import SystemConfiguration

/// 带子里显示的组件（顺序即显示顺序）
enum MetricKind: String, CaseIterable {
    case cpu, gpu, memory, network, disk, battery, fan

    var iconName: String {
        switch self {
        case .cpu:     return "cpu"
        case .gpu:     return "gpu"
        case .memory:  return "memory"
        case .network: return "wifi"
        case .disk:    return "disk"
        case .battery: return "battery"
        case .fan:     return "fan"
        }
    }
}

enum NetKind { case wifi, cellular, ethernet, other }

struct BatteryState {
    var percent: Int
    /// 正在充电
    var charging: Bool
    /// 已接电源（可能充满或在限充，属于「接电但未充电」）
    var onAC: Bool
}

/// 一次采样结果
struct MetricSnapshot {
    var cpu: Double = 0
    var memory: Double = 0
    var netDown: Double = 0
    var netUp: Double = 0
    var netKind: NetKind = .other
    var netIcon: String = "wifi"
    var disk: Double = 0
    var gpu: Double = 0
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cpuNice: Double = 0
    var memCached: Double = 0
    var memApp: Double = 0
    var memWired: Double = 0
    var memCompressed: Double = 0
    var cpuTemp: Double?
    var volumes: [(name: String, used: Double, free: Double)] = []
    /// 占用最高的进程（CPU / 内存各一份）
    /// 按「应用」聚合后的排行（一个 App 的所有进程合在一起）
    var topCPU: [(name: String, value: Double, pids: [Int32], canQuit: Bool)] = []
    var topMem: [(name: String, value: Double, pids: [Int32], canQuit: Bool)] = []
    var batteryCycles: Int?
    var batteryDesign: Int?
    var batteryMax: Int?
    var powerSource: String?
    var load1: Double = 0
    var load5: Double = 0
    var load15: Double = 0
    var memFree: Double = 0
    var memTotal: Double = 0
    var diskFree: Double = 0
    var diskTotal: Double = 0
    var batteryRemaining: Double?      // 分钟
    /// 最近若干次采样（0…1 归一化），画迷你曲线用
    var history: [MetricKind: [Double]] = [:]
    var battery: BatteryState?
    var fan: Double?
    /// 这一轮采样里哪些组件本机真的能读到（设置页与带子共用同一份判断，避免「设置里禁用了、栏上还在显示」）
    var available: [MetricKind: Bool] = [:]

    static let empty = MetricSnapshot()
}

/// 系统指标采集：全部走公开 API（IOKit.ps / Network / Mach）。
/// 风扇是唯一例外，见 `SMC.swift` 的说明。
final class Metrics {

    static let shared = Metrics()

    var onChange: ((MetricSnapshot) -> Void)?

    private var timer: Timer?
    /// 最近一次采样得到的可用性：设置页和带子都读这份，避免两处各自探测导致结论不一致
    private(set) var lastAvailability: [MetricKind: Bool] = [:]
    private var monitor: NWPathMonitor?
    /// NWPath 认为有蜂窝（本机 WWAN）
    private var cellularPath = false
    private var netKind: NetKind = .other
    /// 最近 60s 的速率峰值，用来给蜂窝图标分档（瞬时值在空闲时会掉到 0）
    private var netPeak: (rate: Double, at: TimeInterval) = (0, 0)
    /// 当前主用接口（用于判断图标），接口变化时才写日志
    private var lastNetNote = "-"
    private var prevCPU: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private var prevNet: (inB: UInt64, outB: UInt64, at: TimeInterval)?

    /// 图表历史：每个组件保留最近 24 次采样
    private var history: [MetricKind: [Double]] = [:]
    private static let historyLimit = 24

    func start(interval: TimeInterval = 2) {
        stop()
        startPathMonitor()
        _ = cpuUsage()
        _ = netRates()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let tickStart = CFAbsoluteTimeGetCurrent()
        var s = MetricSnapshot()
        s.cpu = cpuUsage()
        s.memory = memoryUsage()
        let r = netRates()
        s.netDown = r.down
        s.netUp = r.up
        let kind = detectNetKind()
        s.netKind = kind
        let now = CFAbsoluteTimeGetCurrent()
        let instant = max(r.down, r.up)
        if now - netPeak.at > 60 || instant > netPeak.rate { netPeak = (instant, now) } else { netPeak.at = now }
        s.netIcon = Self.networkIcon(kind: kind, peakRate: netPeak.rate)
        s.disk = diskUsage()
        s.battery = battery()
        // 风扇停转（0 RPM）时不显示这个组件：等于「当前没有可显示的转速」
        // 能读到就记下来（0 也是有效读数）；「0 转」属于停转，由带子决定不显示，不改可用性
        let rpm = SMC.fanRPM()
        s.fan = rpm
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) > 0 {
            s.load1 = loads[0]; s.load5 = loads[1]; s.load15 = loads[2]
        }
        (s.memFree, s.memTotal) = memoryTotals()
        (s.diskFree, s.diskTotal) = diskTotals()
        s.batteryRemaining = batteryTimeLeft()
        s.gpu = gpuUsage()
        let cpuDetail = cpuBreakdown()
        s.cpuUser = cpuDetail.user; s.cpuSystem = cpuDetail.system; s.cpuNice = cpuDetail.nice
        s.cpuTemp = SMC.read("Tp09") ?? SMC.read("Tp0T") ?? SMC.read("TC0P")
        let memDetail = memoryBreakdown()
        s.memCached = memDetail.cached; s.memApp = memDetail.app
        s.memWired = memDetail.wired; s.memCompressed = memDetail.compressed
        s.volumes = localVolumes()
        (s.batteryCycles, s.batteryDesign, s.batteryMax, s.powerSource) = batteryInfo()

        if ProcessInfo.processInfo.environment["STATUSX_PROFILE"] == "1" {
            Log.line(String(format: "profile：整轮 %.1f ms", (CFAbsoluteTimeGetCurrent() - tickStart) * 1000))
        }
        let avail = computeAvailability(battery: s.battery, fan: s.fan)
        if !lastAvailability.isEmpty, avail != lastAvailability {
            for (kind, ok) in avail where lastAvailability[kind] != ok {
                Log.line("指标可用性变化：\(kind.rawValue) → \(ok ? "可用" : "读不到")")
            }
        }
        lastAvailability = avail
        s.available = avail
        appendHistory(cpu: s.cpu, memory: s.memory, disk: s.disk,
                      net: max(s.netDown, s.netUp), battery: s.battery?.percent, fan: s.fan)
        s.history = history
        onChange?(s)
    }

    /// 网络类型 → 图标：蜂窝按**最近 60s 的峰值速率**近似分 5G/4G
    /// （macOS 没有公开的蜂窝制式 API；用瞬时速率会在空闲时误报成 3G，所以看一段时间的峰值）
    static func networkIcon(kind: NetKind, peakRate: Double) -> String {
        switch kind {
        case .wifi:     return "wifi"
        case .ethernet: return "ethernet"
        case .other:    return "wifi"
        case .cellular:
            // 空闲时峰值也接近 0，若按 3G 兜底就会出现「5G 手机显示 3G」；所以最低档按 4G 兜底，
            // 只有观测到真实高速率才升级到 5G（3G 图标保留，阈值可再调）
            if peakRate >= 5_000_000 { return "cell-5g" }
            return "cell-4g"
        }
    }

    private func startPathMonitor() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            // 只有「本机自带蜂窝（WWAN）」才靠 NWPath 判断；macOS 上绝大多数情况是 Wi-Fi/有线/手机共享，
            // 那些一律走接口名 + IP 判定（见 detectNetKind）
            if path.usesInterfaceType(.cellular) { self?.cellularPath = true }
            else { self?.cellularPath = false }
        }
        m.start(queue: DispatchQueue(label: "app.statusx.network-path"))
        monitor = m
    }

    // MARK: - 网络类型判定

    /// 主用接口的 BSD 名（en0 / en10 …），取系统动态存储里的 PrimaryInterface
    private func primaryInterfaceBSD() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "app.statusx" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString),
              let dict = value as? [String: Any]
        else { return nil }
        return dict[kSCDynamicStorePropNetPrimaryInterface as String] as? String
    }

    /// 接口对外的硬件端口名：Wi-Fi / iPhone USB / USB 10/100/1000 LAN / 雷雳网桥 …
    private func interfaceDisplayName(_ bsd: String) -> String {
        guard let list = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return "" }
        for intf in list where (SCNetworkInterfaceGetBSDName(intf) as String?) == bsd {
            return (SCNetworkInterfaceGetLocalizedDisplayName(intf) as String?) ?? ""
        }
        return ""
    }

    private func ipv4Address(_ bsd: String) -> String {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return "" }
        defer { freeifaddrs(addrs) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if (ifa.ifa_name.map { String(cString: $0) } ?? "") == bsd,
               let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: host)
                }
            }
            ptr = ifa.ifa_next
        }
        return ""
    }

    /// iPhone/Android 热点常见的网段：172.20.10.0/28、192.168.42–44.0/24
    private static func looksLikePhoneHotspot(_ ip: String) -> Bool {
        if ip.hasPrefix("172.20.10.") { return true }
        for p in ["192.168.42.", "192.168.43.", "192.168.44."] where ip.hasPrefix(p) { return true }
        return false
    }

    /// 真实网络类型：接口名优先，Wi-Fi 再按网段判断是不是手机热点
    private func detectNetKind() -> NetKind {
        if cellularPath { return .cellular }
        guard let bsd = primaryInterfaceBSD() else { return .other }
        let name = interfaceDisplayName(bsd)
        let lower = name.lowercased()
        let ip = ipv4Address(bsd)

        let kind: NetKind
        if lower.contains("iphone") || lower.contains("ipad") || lower.contains("bluetooth") {
            kind = .cellular                      // 手机 USB 共享 / 蓝牙共享
        } else if lower.contains("wi-fi") || lower.contains("airport") || lower.contains("无线") {
            kind = Self.looksLikePhoneHotspot(ip) ? .cellular : .wifi
        } else if lower.contains("ethernet") || lower.contains("lan") || lower.contains("thunderbolt")
                    || lower.contains("bridge") || lower.contains("usb") {
            kind = .ethernet
        } else {
            kind = .other
        }

        let note = "\(bsd) \(name.isEmpty ? "?" : name) \(ip) → \(kind)"
        if note != lastNetNote {
            lastNetNote = note
            Log.line("网络接口：\(note)")
        }
        return kind
    }

    // MARK: - CPU

    private func cpuUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let cur = (user: info.cpu_ticks.0, system: info.cpu_ticks.1,
                   idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { prevCPU = cur }
        guard let p = prevCPU else { return 0 }
        let user = Double(cur.user &- p.user)
        let system = Double(cur.system &- p.system)
        let idle = Double(cur.idle &- p.idle)
        let nice = Double(cur.nice &- p.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return min(1, max(0, (user + system + nice) / total))
    }

    // MARK: - 内存

    private func memoryUsage() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = Double(pageSize)
        let used = (Double(stats.active_count) + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * page
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }
        return min(1, max(0, used / total))
    }

    // MARK: - 网络

    private func interfaceTotals() -> (inB: UInt64, outB: UInt64) {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return (0, 0) }
        defer { freeifaddrs(addrs) }
        var inB: UInt64 = 0
        var outB: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            if ifa.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                inB &+= UInt64(d.ifi_ibytes)
                outB &+= UInt64(d.ifi_obytes)
            }
            ptr = ifa.ifa_next
        }
        return (inB, outB)
    }

    private func netRates() -> (down: Double, up: Double) {
        let t = interfaceTotals()
        let now = CFAbsoluteTimeGetCurrent()
        defer { prevNet = (t.inB, t.outB, now) }
        guard let p = prevNet else { return (0, 0) }
        let dt = max(0.001, now - p.at)
        return (max(0, Double(t.inB &- p.inB) / dt), max(0, Double(t.outB &- p.outB) / dt))
    }

    /// 本机这一项到底能不能读到数据（设置页与带子共用同一份缓存：
    /// 采样每 2s 更新一次，设置页不再自己单独探测，否则会出现「设置里禁用、栏上还在显示」）
    func availability() -> [MetricKind: Bool] {
        if !lastAvailability.isEmpty { return lastAvailability }
        let map = computeAvailability(battery: battery(), fan: SMC.fanRPM())
        lastAvailability = map
        return map
    }

    private func computeAvailability(battery b: BatteryState?, fan f: Double?) -> [MetricKind: Bool] {
        var map: [MetricKind: Bool] = [:]
        for kind in MetricKind.allCases { map[kind] = true }
        map[.battery] = b != nil
        // 风扇：SMC 键读得到就算可用（0 转≠读不到），避免「一会可用一会禁用」来回跳
        map[.fan] = SMC.fanRPM() != nil
        // 调试/截图：STATUSX_UNAVAILABLE=fan,battery 强制标记为读不到（设置页与带子都会照此隐藏）
        if let raw = ProcessInfo.processInfo.environment["STATUSX_UNAVAILABLE"] {
            for name in raw.split(separator: ",") {
                if let k = MetricKind(rawValue: name.trimmingCharacters(in: .whitespaces)) { map[k] = false }
            }
        }
        return map
    }

    // MARK: - GPU / CPU 细分 / 内存细分 / 卷 / 电池详情

    /// GPU 占用（IOAccelerator 的 PerformanceStatistics，键未文档化，取不到就返回 0）
    private func gpuUsage() -> Double {
        guard let match = IOServiceMatching("IOAccelerator") else { return 0 }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, match)
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any],
              let perf = dict["PerformanceStatistics"] as? [String: Any],
              let v = perf["Device Utilization %"] as? Int
        else { return 0 }
        return min(1, max(0, Double(v) / 100))
    }

    private var prevCPUBreakdown: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?

    /// 系统 / 用户 / Nice 三项占比
    private func cpuBreakdown() -> (user: Double, system: Double, nice: Double) {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return (0, 0, 0) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var user: UInt64 = 0, system: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0
        let stride = Int(CPU_STATE_MAX)
        for i in 0..<Int(cpuCount) {
            let base = i * stride
            user &+= UInt64(info[base + Int(CPU_STATE_USER)])
            system &+= UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            idle &+= UInt64(info[base + Int(CPU_STATE_IDLE)])
            nice &+= UInt64(info[base + Int(CPU_STATE_NICE)])
        }
        let cur = (user: UInt32(truncatingIfNeeded: user), system: UInt32(truncatingIfNeeded: system),
                   idle: UInt32(truncatingIfNeeded: idle), nice: UInt32(truncatingIfNeeded: nice))
        defer { prevCPUBreakdown = cur }
        guard let p = prevCPUBreakdown else { return (0, 0, 0) }
        let du = Double(cur.user &- p.user)
        let ds = Double(cur.system &- p.system)
        let di = Double(cur.idle &- p.idle)
        let dn = Double(cur.nice &- p.nice)
        let total = du + ds + di + dn
        guard total > 0 else { return (0, 0, 0) }
        return (du / total, ds / total, dn / total)
    }

    /// 内存细分：已缓存 / App / 联动 / 被压缩
    private func memoryBreakdown() -> (cached: Double, app: Double, wired: Double, compressed: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, 0, 0, 0) }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = Double(pageSize)
        return (Double(stats.external_page_count) * page,
                Double(stats.internal_page_count) * page,
                Double(stats.wire_count) * page,
                Double(stats.compressor_page_count) * page)
    }

    /// 本机的本地卷（名字 + 已用 + 可用）
    private func localVolumes() -> [(name: String, used: Double, free: Double)] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityKey, .volumeIsLocalKey, .volumeIsBrowsableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                              options: [.skipHiddenVolumes]) else { return [] }
        var out: [(String, Double, Double)] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsLocal == true, v.volumeIsBrowsable != false,
                  let total = v.volumeTotalCapacity, let free = v.volumeAvailableCapacity,
                  total > 0 else { continue }
            let name = v.volumeName ?? url.lastPathComponent
            out.append((name, Double(total - free), Double(free)))
        }
        return out
    }

    /// 电池详情：循环次数、设计容量、最大容量、当前电源
    private func batteryInfo() -> (cycles: Int?, design: Int?, max: Int?, source: String?) {
        var cycles: Int?, design: Int?, maxCap: Int?
        if let match = IOServiceMatching("AppleSmartBattery") {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, match)
            if service != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let d = props?.takeRetainedValue() as? [String: Any] {
                    cycles = d["CycleCount"] as? Int
                    // Apple Silicon 上真实容量在 BatteryData 里（顶层只有百分比 MaxCapacity）
                    if let bd = d["BatteryData"] as? [String: Any] {
                        design = bd["DesignCapacity"] as? Int
                        maxCap = bd["FullChargeCapacity"] as? Int
                    }
                    if design == nil { design = d["DesignCapacity"] as? Int }
                    if maxCap == nil { maxCap = d["AppleRawMaxCapacity"] as? Int }
                }
                IOObjectRelease(service)
            }
        }
        var source: String?
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
           let ps = list.first,
           let raw = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue(),
           let desc = raw as? [String: Any] {
            source = desc[kIOPSPowerSourceStateKey as String] as? String
        }
        return (cycles, design, maxCap, source)
    }

    /// 只在面板可见时调用：进程枚举约 10–18ms，没必要每 2 秒都跑
    @discardableResult
    func sampleProcessTops() -> (cpu: [(String, Double, [Int32], Bool)], mem: [(String, Double, [Int32], Bool)]) {
        lastTops = topProcesses()
        return lastTops
    }

    /// 最近一次进程排行（面板刷新时直接用，不重复枚举）
    private(set) var lastTops: (cpu: [(String, Double, [Int32], Bool)], mem: [(String, Double, [Int32], Bool)]) = ([], [])

    // MARK: - 进程占用排行

    private var prevProcCPU: [Int32: (time: Double, at: TimeInterval)] = [:]

    /// CPU / 内存占用最高的几个前台 App（用 libproc 的 rusage，公开接口）
    /// 全进程排行（不只前台 App）：用 libproc 的 rusage 取真实 CPU 时间与常驻内存
    private func topProcesses() -> (cpu: [(String, Double, [Int32], Bool)], mem: [(String, Double, [Int32], Bool)]) {
        let now = CFAbsoluteTimeGetCurrent()
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return ([], []) }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard n > 0 else { return ([], []) }

        var groups: [String: (name: String, cpu: Double, mem: Double, pids: [Int32], canQuit: Bool)] = [:]
        var alive: [Int32: (time: Double, at: TimeInterval)] = [:]

        for i in 0..<Int(n) {
            let pid = pids[i]
            guard pid > 1 else { continue }   // 自己仍然列出来（但不给 ✕），方便看自身占用
            var info = rusage_info_v2()
            let kr = withUnsafeMutablePointer(to: &info) { ptr -> Int32 in
                ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard kr == 0 else { continue }   // 其它用户的进程会失败，跳过即可

            // ri_user_time / ri_system_time 的单位是 **mach 时间戳**（Apple Silicon 约 24MHz），
            // 不是纳秒；直接用 1e9 除会小 40 多倍（实测 2 秒满载只算出 24ms）
            let total = Self.seconds(info.ri_user_time + info.ri_system_time)
            alive[pid] = (total, now)
            let cpu: Double
            if let prev = prevProcCPU[pid], now > prev.at + 0.2 {
                // 差值 / 间隔 = 占「一个核心」的比例；再除以核心数，换算成「占全部核心」的百分比，
                // 这样和顶部「系统 / 用户」是同一量纲，能对得上
                let cores = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
                cpu = max(0, (total - prev.time) / (now - prev.at) / cores)
            } else {
                cpu = 0
            }

            var nameBuf = [CChar](repeating: 0, count: 256)
            var name = "pid \(pid)"
            if proc_name(pid, &nameBuf, 256) > 0 { name = String(cString: nameBuf) }

            // 按应用聚合：同一个 .app 下的所有进程算一个条目
            let group = appGroup(pid: pid, fallbackName: name)
            let quitOK = canQuit(pid: pid, name: name)
            if var existing = groups[group.key] {
                existing.cpu += cpu
                existing.mem += Double(info.ri_phys_footprint)
                existing.pids.append(pid)
                existing.canQuit = existing.canQuit && quitOK
                groups[group.key] = existing
            } else {
                groups[group.key] = (group.name, cpu, Double(info.ri_phys_footprint), [pid], quitOK)
            }
        }
        prevProcCPU = alive

        // 多取一些：卡片里只露 5 行，其余可以滚出来
        let all = Array(groups.values)
        let cpuTop = all.sorted { $0.cpu > $1.cpu }.prefix(20).map { ($0.name, $0.cpu, $0.pids, $0.canQuit) }
        let memTop = all.sorted { $0.mem > $1.mem }.prefix(20).map { ($0.name, $0.mem, $0.pids, $0.canQuit) }
        return (Array(cpuTop), Array(memTop))
    }

    private static let timebase: mach_timebase_info_data_t = {
        var t = mach_timebase_info_data_t()
        mach_timebase_info(&t)
        return t
    }()

    /// mach 时间戳 → 秒
    static func seconds(_ ticks: UInt64) -> Double {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    /// 能不能给这个进程显示退出按钮：只允许当前用户自己的、非系统路径的进程
    private func canQuit(pid: Int32, name: String) -> Bool {
        guard pid > 1 else { return false }
        guard pid != getpid() else { return false }   // 自己是不能关的
        if Self.forbiddenProcessNames.contains(name) { return false }

        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let got = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size)
        guard got == size else { return false }
        guard bsd.pbi_uid == getuid() else { return false }   // root / 其它用户的进程一律不给

        var pathBuf = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &pathBuf, 4096) > 0 {
            let path = String(cString: pathBuf)
            for prefix in ["/System/", "/usr/sbin/", "/usr/libexec/", "/sbin/", "/usr/bin/"] {
                if path.hasPrefix(prefix) { return false }
            }
        }
        return true
    }

    static let forbiddenProcessNames: Set<String> = [
        "launchd", "kernel_task", "WindowServer", "loginwindow", "Finder",
        "Dock", "SystemUIServer", "ControlCenter", "NotificationCenter",
        "logind", "runningboardd"
    ]

    /// 进程属于哪个「应用」：路径里带 .app 就取 App 名，否则用可执行名
    private func appGroup(pid: Int32, fallbackName: String) -> (key: String, name: String) {
        var pathBuf = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &pathBuf, 4096) > 0 else {
            return (fallbackName, fallbackName)
        }
        let path = String(cString: pathBuf)
        if let range = path.range(of: ".app/") {
            let appPath = String(path[..<range.lowerBound]) + ".app"
            let name = (appPath as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            return (appPath, name)
        }
        let exe = (path as NSString).lastPathComponent
        return ("exe:" + exe, exe)
    }

    // MARK: - 历史与容量

    private func appendHistory(cpu: Double, memory: Double, disk: Double,
                               net: Double, battery: Int?, fan: Double?) {
        func push(_ kind: MetricKind, _ v: Double) {
            var arr = history[kind] ?? []
            arr.append(min(1, max(0, v)))
            if arr.count > Self.historyLimit { arr.removeFirst(arr.count - Self.historyLimit) }
            history[kind] = arr
        }
        push(.cpu, cpu)
        push(.memory, memory)
        push(.disk, disk)
        push(.network, min(1, net / 5_000_000))
        push(.battery, Double(battery ?? 0) / 100)
        push(.fan, min(1, (fan ?? 0) / 3000))
    }

    /// 内存总量与近似空闲（总量 − 已用）
    private func memoryTotals() -> (free: Double, total: Double) {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = Double(pageSize)
        let used = (Double(stats.active_count) + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * page
        return (max(0, total - used), total)
    }

    private func diskTotals() -> (free: Double, total: Double) {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = (attrs[.systemSize] as? NSNumber)?.doubleValue,
              let free = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue
        else { return (0, 0) }
        return (free, total)
    }

    /// 电池剩余时间（分钟）：用电池时是「还能用多久」，充电时是「充满还要多久」
    private func batteryTimeLeft() -> Double? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for ps in list {
            guard let raw = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue(),
                  let desc = raw as? [String: Any] else { continue }
            let charging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
            let key = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let minutes = desc[key as String] as? Int, minutes > 0 { return Double(minutes) }
        }
        return nil
    }

    // MARK: - 硬盘

    /// 启动卷已用比例：`1 − 可用 / 总容量`
    private func diskUsage() -> Double {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/"),
              let total = (attrs[.systemSize] as? NSNumber)?.doubleValue, total > 0,
              let free = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue
        else { return 0 }
        return min(1, max(0, (total - free) / total))
    }

    // MARK: - 电池

    private func battery() -> BatteryState? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for ps in list {
            guard let raw = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue(),
                  let desc = raw as? [String: Any],
                  let cap = desc[kIOPSCurrentCapacityKey as String] as? Int,
                  let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int, maxCap > 0
            else { continue }
            let charging = (desc[kIOPSIsChargingKey as String] as? Bool) ?? false
            let onAC = (desc[kIOPSPowerSourceStateKey as String] as? String) == (kIOPSACPowerValue as String)
            return BatteryState(percent: Int((Double(cap) / Double(maxCap) * 100).rounded()),
                                charging: charging,
                                onAC: onAC)
        }
        return nil
    }
}
