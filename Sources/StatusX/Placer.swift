import Cocoa

/// StatusX 自己那条状态项的唯一控制器：**固定宽度，不做任何排布**。
///
/// 2026-10-30 定案：StatusX 不再搬动菜单栏里的任何项。
/// 顺序由用户自己用 ⌘ + 拖拽调整（系统原生能力），我们只负责：
/// 1. 把自己的状态项设成设计宽度（310px）；
/// 2. 宽度确定后通知 UI 重画带子内容。
final class Placer {

    /// 设计宽度：固定值，不随其它应用增减而变化
    static let bandWidth: CGFloat = 310

    /// 视口左缘 = 刘海（摄像头）右缘。硬件固定值；无刘海机型退回一个安全距离。
    static var zoneStart: CGFloat {
        if let area = NSScreen.main?.auxiliaryTopRightArea, area.width > 1 {
            return area.minX + 2
        }
        return 120
    }

    /// 宽度落定后回调（带上最终宽度），由界面层重画标识
    var onWidthChanged: ((CGFloat) -> Void)?

    private let item: NSStatusItem
    private var width: CGFloat
    /// 自动宽度时由 `renderStrip` 决定长度，这里不再写死
    private var autoWidth = true
    init(config: Config, item: NSStatusItem) {
        self.item = item
        self.width = CGFloat(config.bandWidth)
        self.autoWidth = config.autoWidth ?? true
    }

    /// 配置变更：只跟着改宽度
    func apply(_ config: Config) {
        width = CGFloat(config.bandWidth)
        autoWidth = config.autoWidth ?? true
    }

    /// 把状态项设成固定宽度。reason 只用于日志区分触发来源。
    func layout(reason: String, completion: (() -> Void)? = nil) {
        if !autoWidth { item.length = width }
        onWidthChanged?(autoWidth ? item.length : width)
        Log.line(autoWidth ? "带宽：按组件自适应（上限 \(Int(width))px · \(reason)）"
                           : "带宽 \(Int(width))px（固定值 · \(reason)）")
        // 布局由系统完成，帧要过一帧之后才准；延迟读一次，日志才不会被旧值误导
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if let me = MBar.own() {
                Log.line("实际落位：x=\(Int(me.frame.origin.x)) 宽=\(Int(me.frame.width))（视口左缘 \(Int(Placer.zoneStart))）")
            }
        }
        completion?()
    }
}
