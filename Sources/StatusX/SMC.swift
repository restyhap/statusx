import IOKit

/// 读风扇转速（AppleSMC 的 `F0Ac`）。
///
/// 说明：风扇转速没有公开的系统 API，只能走 SMC 这个 IOKit 用户客户端。
/// 这是本项目唯一一处「非文档化接口」，并且全程容错：拿不到就返回 nil，界面上不显示。
///
/// 结构体按 AppleSMC 的 `SMCKeyData_t` 原样声明（Natural alignment，整体 80 字节），
/// 不要用「字节偏移量硬编码」，偏移算错会静默读出垃圾值（2026-10-30 实测第一次就踩了）。
enum SMC {

    private static let kernelIndex: UInt32 = 2
    private static let cmdReadKeyInfo: UInt8 = 9
    private static let cmdReadBytes: UInt8 = 5

    private struct Vers {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct PLimit {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    /// 结构对齐要跟 C 版一致：C 里这个结构体因 4 字节对齐补到 12 字节，
    /// Swift 不会补（实测只有 9），所以后面显式留 3 字节填充，否则整个 KeyData 变成 76 字节、
    /// 后续字段全部错位，内核只会回一个拿不到数据的成功（2026-10-30 实测踩坑）。
    private struct KeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
        var padding: (UInt8, UInt8, UInt8) = (0, 0, 0)
    }

    private struct KeyData {
        var key: UInt32 = 0
        var vers = Vers()
        var pLimitData = PLimit()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static var conn: io_connect_t = 0
    private static var tried = false

    /// 主风扇转速（RPM）；读取失败返回 nil
    static func fanRPM() -> Double? { read("F0Ac") }

    /// 读任意 SMC 键（温度等）；读不到返回 nil
    static func read(_ name: String) -> Double? {
        guard open() else { return nil }
        var input = KeyData()
        input.key = fourCC(name)
        input.data8 = cmdReadKeyInfo
        guard let output = run(input), output.result == 0,
              output.keyInfo.dataSize > 0, output.keyInfo.dataSize <= 32 else { return nil }

        let size = Int(output.keyInfo.dataSize)
        let type = output.keyInfo.dataType
        input = KeyData()
        input.key = fourCC(name)
        input.data8 = cmdReadBytes
        input.keyInfo.dataSize = UInt32(size)
        input.keyInfo.dataType = type
        guard let read = run(input), read.result == 0 else { return nil }

        let raw = bytesArray(read.bytes, size)
        switch type {
        case fourCC("flt "):
            guard raw.count >= 4 else { return nil }
            let v = raw.withUnsafeBytes { $0.load(as: Float32.self) }
            return v.isFinite && v >= 0 ? Double(v) : nil
        case fourCC("fpe2"):
            guard raw.count >= 2 else { return nil }
            return Double((UInt16(raw[0]) << 8) | UInt16(raw[1])) / 4
        case fourCC("sp78"):
            guard raw.count >= 2 else { return nil }
            return Double(Int16(bitPattern: (UInt16(raw[0]) << 8) | UInt16(raw[1]))) / 256
        default:
            return nil
        }
    }

    /// 诊断用：返回原始 keyInfo（长度 与 类型四字符）
    static func fanKeyInfo() -> (size: UInt32, type: String)? {
        guard open() else { return nil }
        var input = KeyData()
        input.key = fourCC("F0Ac")
        input.data8 = cmdReadKeyInfo
        guard let out = run(input), out.result == 0 else { return nil }
        let t = out.keyInfo.dataType
        let chars = [24, 16, 8, 0].map { UInt8((t >> UInt32($0)) & 0xff) }
        return (out.keyInfo.dataSize, String(bytes: chars, encoding: .ascii) ?? "????")
    }

    // MARK: - 底层

    private static func open() -> Bool {
        if tried { return conn != 0 }
        tried = true
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        return IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess
    }

    private static func run(_ input: KeyData) -> KeyData? {
        var `in` = input
        var out = KeyData()
        var outSize = MemoryLayout<KeyData>.size
        let kr = withUnsafeBytes(of: &`in`) { inRaw in
            withUnsafeMutableBytes(of: &out) { outRaw in
                IOConnectCallStructMethod(conn, kernelIndex,
                                          inRaw.baseAddress, MemoryLayout<KeyData>.size,
                                          outRaw.baseAddress, &outSize)
            }
        }
        return kr == kIOReturnSuccess ? out : nil
    }

    private static func fourCC(_ s: String) -> UInt32 {
        var v: UInt32 = 0
        for b in s.utf8.prefix(4) { v = (v << 8) | UInt32(b) }
        return v
    }

    private static func bytesArray(_ tuple: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8), _ size: Int) -> [UInt8] {
        withUnsafeBytes(of: tuple) { raw in
            Array(raw.prefix(min(size, raw.count)))
        }
    }
}
