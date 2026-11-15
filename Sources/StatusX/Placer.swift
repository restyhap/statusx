import Cocoa

/// StatusX 自己那条状态项的唯一控制器。
///
/// 2026-11-15 定案：310 是**上限**，不是固定值。
/// `NSStatusItem.length` 只是「申请」宽度：菜单栏放不下时，系统会把整项推到刘海下面
/// 或收进 `<<`，之后再改窄也回不来（一次创建就决定了落点）。
/// 所以这里先用最窄宽度落地，确认它真的出现在栏上，再用二分法找出「这次还能长到多宽」，
/// 一次性定下来——之后数值/组件数变化都不再改宽度。
final class Placer {

    /// 设计宽度上限：永久不变
    static let bandWidth: CGFloat = 310
    /// 硬上限（与 bandWidth 同值，语义更明确）
    static let maxWidth: CGFloat = 310
    /// 校准用的初始宽度：只求能落在栏上，不求好看
    static let probeWidth: CGFloat = 18
    /// 二分收敛精度：最后停在 6px 以内
    static let tolerance: CGFloat = 6

    /// 视口左缘 = 刘海（摄像头）右缘。硬件固定值；无刘海机型退回一个安全距离。
    static var zoneStart: CGFloat {
        if let area = NSScreen.main?.auxiliaryTopRightArea, area.width > 1 {
            return area.minX + 2
        }
        return 120
    }

    /// 宽度落定后回调（带上最终宽度），由界面层重画标识
    var onWidthChanged: ((CGFloat) -> Void)?

    /// 当前带宽（已封顶、已按可用槽位收窄）
    private(set) var width: CGFloat = Placer.probeWidth

    private let item: NSStatusItem
    init(config: Config, item: NSStatusItem) {
        self.item = item
    }

    /// 配置变更：宽度只受菜单栏空间限制，不理会 bandWidth/autoWidth 的旧配置值
    func apply(_ config: Config) {}

    /// 启动 / 屏幕变化 / 唤醒时校准一次。
    ///
    /// 1. 先按最窄宽度落一次（18px）。如果连它都不在栏上，说明这次没有空位，直接停住；
    /// 2. 否则二分找「还能长到多宽」：每次改长度后用 AX 确认自己还在 extras 列表里；
    /// 3. 最后停在上界内，再核对一次，不在就退回最窄。
    ///
    /// 判「在不在栏上」用 AX（`MBar.own()`）：被收进 `<<` 时窗口 frame 可能仍在屏幕内，
    /// 只有 AX 的 extras 列表能可靠区分（2026-11-15 实测：frame x=1162 看着正常，AX 却没有该项）。
    func settle(reason: String, completion: @escaping (CGFloat) -> Void) {
        item.length = Self.probeWidth
        // 改长度会让系统异步重建按钮，等布局完成再量
        after(0.30) { [weak self] in
            guard let self else { return }
            guard self.isVisible else {
                self.finish(width: Self.probeWidth, reason: reason,
                            note: "最窄 \(Int(Self.probeWidth))px 也放不进菜单栏", completion: completion)
                return
            }
            self.search(low: Self.probeWidth, high: Self.maxWidth, reason: reason, completion: completion)
        }
    }

    /// 二分：low 已知可见，high 未知。收敛到 6px 以内后停 low。
    private func search(low: CGFloat, high: CGFloat, reason: String,
                        completion: @escaping (CGFloat) -> Void) {
        guard high - low > Self.tolerance else {
            applyWidth(low, reason: reason, completion: completion)
            return
        }
        let mid = (low + high) / 2
        item.length = mid
        after(0.32) { [weak self] in
            guard let self else { return }
            if self.isVisible {
                self.search(low: mid, high: high, reason: reason, completion: completion)
            } else {
                self.search(low: low, high: mid, reason: reason, completion: completion)
            }
        }
    }

    /// 用最终宽度落定，并再核对一次（二分过程中可能正好停在边界外）
    private func applyWidth(_ target: CGFloat, reason: String,
                            completion: @escaping (CGFloat) -> Void) {
        let capped = min(Self.maxWidth, max(Self.probeWidth, target))
        item.length = capped
        after(0.32) { [weak self] in
            guard let self else { return }
            if self.isVisible {
                self.finish(width: capped, reason: reason, note: nil, completion: completion)
            } else {
                self.item.length = Self.probeWidth
                self.after(0.30) {
                    self.finish(width: Self.probeWidth, reason: reason,
                                note: "\(Int(capped))px 落不进菜单栏，退回最窄", completion: completion)
                }
            }
        }
    }

    private func finish(width: CGFloat, reason: String, note: String?,
                        completion: @escaping (CGFloat) -> Void) {
        self.width = width
        let detail = note.map { "（\($0)）" } ?? ""
        Log.line("带宽校准：\(Int(width))px\(detail)（上限 \(Int(Self.maxWidth)) · \(reason)）")
        onWidthChanged?(width)
        completion(width)
    }

    private func after(_ seconds: Double, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
    }

    /// 项是否真的在菜单栏可见区。
    /// 有辅助功能权限时以 AX 为准；没有权限时看窗口落在哪里。
    var isVisible: Bool {
        if MBar.trusted() {
            return MBar.own() != nil
        }
        // 没有辅助功能权限：macOS 26 的 CGWindowList 不再列出自己的状态项窗口
        //（实测本进程窗口数 0，窗口服务器兜底永远是 false），改用窗口位置判断：
        // 放得下时窗口落在刘海右侧（x ≥ zoneStart）；被折叠/推走时系统会把窗口推到
        // 刘海左侧或屏幕外（实测 600px 时 x=612，zoneStart=1140）。
        guard let f = item.button?.window?.frame else { return false }
        return f.width > 4
            && f.minX >= Placer.zoneStart - 1
            && f.maxX <= MBar.screenWidth - 4
    }
}
