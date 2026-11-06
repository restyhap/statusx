import Cocoa

/// 简易日志：同时写 stderr 与 /tmp/statusx.log
enum Log {
    private static let handle: FileHandle? = {
        let path = "/tmp/statusx.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    static func line(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let text = "[\(ts)] \(msg)\n"
        FileHandle.standardError.write(text.data(using: .utf8)!)
        handle?.write(text.data(using: .utf8)!)
    }

    static func table(_ items: [MBItem]) -> String {
        items.map { it in
            String(format: "x=%4d w=%3d h=%2d  %@%@",
                   Int(it.frame.origin.x), Int(it.frame.width), Int(it.frame.height),
                   it.appName, it.actions.isEmpty ? "" : "  [\(it.actions.joined(separator: ","))]")
        }.joined(separator: "\n")
    }
}
