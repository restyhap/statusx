import Cocoa

/// launchd 托管的服务（brew services、LaunchAgents / LaunchDaemons 都在这套里）
struct LaunchService {
    let label: String
    /// `gui/501` 或 `system`
    let domain: String

    var isDaemon: Bool { domain == "system" }
}

enum LaunchServiceScanner {

    /// 找出这个进程（或它的祖先）属于哪个 launchd 服务。
    ///
    /// 不用 plist 的 Program 路径去匹配——很多 plist 里写的是 `bash`/`python` 这类解释器，
    /// 会把所有同名进程都误判成服务（实测 WeChat 的 plist 就是 `/bin/bash`）。
    /// 改成问 launchd 自己：`launchctl print <domain>` 里每个服务都有 `pid = N`，拿它和进程祖先链比对。
    static func service(forPID pid: Int32) -> LaunchService? {
        let uid = getuid()
        var map: [Int32: LaunchService] = [:]

        // 用户域：`launchctl list` 直接给出 pid ↔ label（pid 为 "-" 表示没在跑）
        for line in launchctlRun(["list"]).split(separator: "\n").dropFirst() {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3, let pid = Int32(parts[0]) else { continue }
            let label = String(parts[2]).trimmingCharacters(in: .whitespaces)
            map[pid] = LaunchService(label: label, domain: "gui/\(uid)")
        }

        // 系统域：`launchctl print system` 里每个服务块有 pid = N
        for (label, servicePID) in parseBlocks(launchctlRun(["print", "system"])) {
            if map[servicePID] == nil {
                map[servicePID] = LaunchService(label: label, domain: "system")
            }
        }
        guard !map.isEmpty else { return nil }

        var current = pid
        for _ in 0..<6 {
            if let svc = map[current] { return svc }
            guard let parent = parentPID(current), parent > 1 else { return nil }
            current = parent
        }
        return nil
    }

    private static func launchctlRun(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    /// 解析 `launchctl print` 输出：形如
    ///   com.example.job = {
    ///       active count = 1
    ///       pid = 4321
    ///   }
    private static func parseBlocks(_ output: String) -> [(String, Int32)] {
        var result: [(String, Int32)] = []
        var currentLabel: String?
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix("= {") {
                let label = line.replacingOccurrences(of: "= {", with: "")
                    .trimmingCharacters(in: .whitespaces)
                currentLabel = label
            } else if line.hasPrefix("pid = "), let label = currentLabel {
                if let pid = Int32(line.replacingOccurrences(of: "pid = ", with: "")) {
                    result.append((label, pid))
                }
            }
        }
        return result
    }

    private static func parentPID(_ pid: Int32) -> Int32? {
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size else { return nil }
        return Int32(bitPattern: bsd.pbi_ppid)
    }

    /// 停止服务：bootout 之后 launchd 不会再把它拉起来
    static func stop(_ service: LaunchService) -> String {
        let target = "\(service.domain)/\(service.label)"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", target]
        let errPipe = Pipe()
        p.standardError = errPipe
        do {
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus == 0 { return "服务已停止（\(service.label)）" }
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return "停止失败：\(err.isEmpty ? "退出码 \(p.terminationStatus)" : err.trimmingCharacters(in: .whitespacesAndNewlines))"
        } catch {
            return "停止失败：\(error.localizedDescription)"
        }
    }
}
