import Foundation

/// 配置文件：~/Library/Application Support/StatusX/config.json
struct Config: Codable {
    /// StatusX 状态项的固定宽度（设计值 310）
    var bandWidth: Double = 310
    /// 310px 带子里显示哪些指标（cpu/memory/network/battery/fan）；不写 = 全部
    var metrics: [String]? = nil
    /// 是否在图标旁显示数值
    var metricValues: Bool? = nil
    /// 带子宽度是否按启用的组件自动分配（上限 still `bandWidth`）
    var autoWidth: Bool? = nil
    /// 每个组件自己的显示配置（键是 MetricKind.rawValue）
    var metricSettings: [String: MetricSettings]? = nil
    /// 组件的显示顺序（全部 6 个组件，含未启用的）；不写 = 默认顺序
    var metricOrder: [String]? = nil
    /// 面板背景：`popover` = 系统毛玻璃（正式版）｜`white` = 纯白（测试/截图用）。
    /// 不写等于 popover，所以老配置文件不受影响。
    var panelBackground: String? = nil
    /// 登录项（开机自启）。写入系统，不靠这个字段生效，只用于回显状态。
    var launchAtLogin: Bool? = nil
    /// 面板列表排序：`name`（按名称）｜`position`（按菜单栏位置）
    var panelSort: String? = nil
    /// 面板是否显示「菜单栏」统计卡片
    var showStatsCard: Bool? = nil
    /// 面板列表最多可见行数（超出滚动）
    var maxListRows: Int? = nil
    /// 面板宽度
    var panelWidth: Double? = nil
    /// 界面语言：`en`｜`zh-Hans`｜`zh-Hant`｜`ko`｜`de`｜`fr`｜`es`｜`pt`｜`ru`。不写 = 跟随系统
    var language: String? = nil
    /// 关闭设置窗口时：`minimize`（留在菜单栏）｜`quit`（退出 StatusX）。不写 = minimize
    var closeAction: String? = nil

    /// 老配置里的键名（`minWidth` 是 `bandWidth` 的前身）
    private struct LegacyKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
    }

    init() {}

    /// 手写解码：老配置里没有 `bandWidth`（它的前身叫 `minWidth`），
    /// 合成解码遇到缺省键会整体失败、把整份配置清空（2026-10-30 实测踩到），所以逐个做兜底。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKey.self)
        let legacyWidth = try legacy.decodeIfPresent(Double.self, forKey: LegacyKey(stringValue: "minWidth")!)
        bandWidth = try c.decodeIfPresent(Double.self, forKey: .bandWidth) ?? legacyWidth ?? 310
        metrics = try c.decodeIfPresent([String].self, forKey: .metrics)
        metricValues = try c.decodeIfPresent(Bool.self, forKey: .metricValues)
        autoWidth = try c.decodeIfPresent(Bool.self, forKey: .autoWidth)
        metricSettings = try c.decodeIfPresent([String: MetricSettings].self, forKey: .metricSettings)
        metricOrder = try c.decodeIfPresent([String].self, forKey: .metricOrder)
        panelBackground = try c.decodeIfPresent(String.self, forKey: .panelBackground)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin)
        panelSort = try c.decodeIfPresent(String.self, forKey: .panelSort)
        showStatsCard = try c.decodeIfPresent(Bool.self, forKey: .showStatsCard)
        maxListRows = try c.decodeIfPresent(Int.self, forKey: .maxListRows)
        panelWidth = try c.decodeIfPresent(Double.self, forKey: .panelWidth)
        language = try c.decodeIfPresent(String.self, forKey: .language)
        closeAction = try c.decodeIfPresent(String.self, forKey: .closeAction)
    }

    /// 取某个组件的配置，没有就用默认
    func settings(for kind: MetricKind) -> MetricSettings {
        metricSettings?[kind.rawValue] ?? .defaults(kind)
    }

    mutating func setSettings(_ s: MetricSettings, for kind: MetricKind) {
        var m = metricSettings ?? [:]
        m[kind.rawValue] = s
        metricSettings = m
    }

    static let dir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/StatusX", isDirectory: true)
    static let url = dir.appendingPathComponent("config.json")

    static func load() -> Config {
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else {
            let fresh = Config()
            fresh.save()
            return fresh
        }
        return cfg
    }

    func save() {
        try? FileManager.default.createDirectory(at: Config.dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: Config.url) }
    }
}
