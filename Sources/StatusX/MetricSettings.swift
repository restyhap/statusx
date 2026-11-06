import Foundation

/// 单个组件的显示配置（存在 `Config.metricSettings` 里，键是 `MetricKind.rawValue`）
struct MetricSettings: Codable, Equatable {
    var showIcon: Bool = true
    var showText: Bool = true
    var showChart: Bool = false
    /// 数值项 id，顺序即显示顺序（带子里最多显示 2 行）
    var values: [String] = []

    static func defaults(_ kind: MetricKind) -> MetricSettings {
        switch kind {
        case .cpu:     return MetricSettings(values: ["usage"])
        case .gpu:     return MetricSettings(values: ["usage"])
        case .memory:  return MetricSettings(values: ["used"])
        case .network: return MetricSettings(values: ["down", "up"])
        case .disk:    return MetricSettings(values: ["usage"])
        case .battery: return MetricSettings(values: ["percent"])
        case .fan:     return MetricSettings(values: ["rpm"])
        }
    }
}

/// 可选的数值项：id + 文案 + 是否默认选中
struct MetricValueOption {
    let id: String
    let label: String
}

enum MetricCatalog {

    /// 带子里最多显示的行数（22pt 高，两行 8.5pt 是上限）
    static let maxLines = 2

    static func options(_ kind: MetricKind) -> [MetricValueOption] {
        switch kind {
        case .cpu:
            return [MetricValueOption(id: "usage",  label: Str.valUsage),
                    MetricValueOption(id: "temp",   label: Str.valTemp),
                    MetricValueOption(id: "load1",  label: Str.valLoad1),
                    MetricValueOption(id: "load5",  label: Str.valLoad5),
                    MetricValueOption(id: "load15", label: Str.valLoad15)]
        case .gpu:
            return [MetricValueOption(id: "usage", label: Str.valUsage)]
        case .memory:
            return [MetricValueOption(id: "used",  label: Str.valUsed),
                    MetricValueOption(id: "free",  label: Str.valFree),
                    MetricValueOption(id: "total", label: Str.valTotal)]
        case .network:
            return [MetricValueOption(id: "down", label: Str.valDown),
                    MetricValueOption(id: "up",   label: Str.valUp)]
        case .disk:
            return [MetricValueOption(id: "usage", label: Str.valUsagePercent),
                    MetricValueOption(id: "free",  label: Str.valFree),
                    MetricValueOption(id: "total", label: Str.valTotal)]
        case .battery:
            return [MetricValueOption(id: "percent",   label: Str.valPercent),
                    MetricValueOption(id: "remaining", label: Str.valRemaining)]
        case .fan:
            return [MetricValueOption(id: "rpm", label: Str.valRPM)]
        }
    }

    static func label(_ kind: MetricKind, _ id: String) -> String {
        options(kind).first { $0.id == id }?.label ?? id
    }
}
