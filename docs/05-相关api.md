# 05 相关 API 速查（函数级 · 2026-10-26）

> 用途：给设计评审用。每行一个函数，一句话说明作用；标了「实测」的是本机（macOS 27 / 2056×1329 / 刘海右缘 1138）跑过并记录结果的。
> 签名以本机 `MacOSX.sdk` 为准。

## 0. 先看需求 → API 链

| 需求 | 用到的东西 |
|---|---|
| 2.2/2.3 视口与默认宽度 | `NSScreen.auxiliaryTopRightArea` + AX 读系统项位置 + `NSStatusItem.length` |
| 2.4 显示应用栏 / 加边框 | `NSView`(layer) + `NSDraggingSource/Destination` + `NSStatusItem.length` |
| 2.5 排布顺序 | `CGEvent`（合成 ⌘-拖）+ `AXUIElementCopyAttributeValue`（读位置） |
| 换序后校验 / 自愈 | `AXUIElementCopyAttributeValue` + `NSApplicationDidChangeScreenParametersNotification` + `NSWorkspaceDidWakeNotification` |

---

## 1. 自己的状态项（AppKit，公开）

| 函数 / 属性 | 一句话作用 | 本项目用途 |
|---|---|---|
| `NSStatusBar.system` | 取系统菜单栏单例 | 创建/移除状态项 |
| `NSStatusBar.statusItem(withLength:)` | 新建状态项并指定初始宽度 | 启动时建 StatusX 项 |
| `NSStatusBar.removeStatusItem(_:)` | 移除状态项 | 退出清理 |
| `NSStatusItem.length` | 读/写状态项宽度（点为单位） | **核心**：带宽 = 视口 − 块宽 |
| `NSStatusItem.isVisible` | 显示/隐藏自己 | 折叠兜底 |
| `NSStatusItem.behavior` | 行为位（`.removalAllowed` / `.terminationOnRemoval`） | ⌘-拖可移除，避免误删 |
| `NSStatusItem.autosaveName` | 让系统记住**自己**的位置 | 设为 `statusx` |
| `NSStatusItem.button` | 拿到按钮（`NSStatusBarButton`，继承 `NSButton`） | 挂自绘子视图 |
| `NSStatusItem.menu` | 给状态项挂下拉菜单 | 不用（改用自定义面板窗口） |
| `NSStatusItem.variableLength` / `.squareLength` | 宽度常量：随内容 / 等高等宽 | 计算最小宽参考 |
| `NSStatusBarButton.image` / `.title` / `.imagePosition` | 按钮内容与排布 | 图像由子视图负责，按钮留空 |
| `NSStatusBarButton.appearsDisabled` | 灰显按钮但不禁用点击 | 备用 |
| `NSStatusBarButton.sendAction(on:)` | 指定哪些事件触发 action | 左键按下即开面板 |
| `NSButton.target` / `.action` | 点击回调 | `togglePanel` |
| `NSView.addSubview(_:)` / `.frame` | 加子视图、定位 | 带子贴左子视图 |
| `NSView.hitTest(_:)` | 命中测试（返回 nil = 点击穿透） | `StripHostView` 不抢点击 |

## 2. 合成 ⌘-拖拽（换序，CoreGraphics 公开）

| 函数 / 常量 | 一句话作用 | 备注 |
|---|---|---|
| `CGEventSource(stateID: .hidSystemState)` | 建事件源（模拟硬件层输入） | |
| `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` | 造一个鼠标事件 | |
| `.mouseMoved` | 光标移动 | 先移动到起点 |
| `.leftMouseDown` | 按下左键 | 配合 `.maskCommand` |
| `.leftMouseDragged` | 拖动（按住并移动） | 分多步发，每步 `usleep` 20~40ms |
| `.leftMouseUp` | 松开 | 系统据此完成落位 |
| `CGEvent.flags = .maskCommand` | 事件带「⌘ 按下」标志 | **菜单栏换序的必要条件** |
| `CGEvent.post(tap: .cghidEventTap)` | 投递到系统输入流 | 需要辅助功能授权 |
| `CGWarpMouseCursorPosition(_:)` | 直接改光标坐标 | 起点对齐用 |
| `CGAssociateMouseAndMouseCursorPosition(1)` | 恢复光标跟随 | 拖拽后复位 |
| `usleep(_:)` | 微秒级等待 | 每步之间让系统重排 |
| `NSEvent.mouseLocation` | 当前光标位置（**左下原点**） | 与 CGEvent 左上原点需换算 |

> 坐标坑：`CGEvent` 用**左上原点**的屏幕坐标，`NSEvent.mouseLocation` 是**左下原点**，换算 `y' = 屏幕高 − y`；Retina 下 CGEvent 仍用点（不是像素）。

## 3. 辅助功能 AX（读别人状态项 / 按下）

| 函数 / 常量 | 一句话作用 | 实测 |
|---|---|---|
| `AXIsProcessTrusted()` | 是否已获辅助功能授权 | true |
| `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` | 请求授权并弹系统提示 | 备用 |
| `AXUIElementCreateApplication(pid)` | 以某进程为根的 AX 元素 | 正常 |
| `AXUIElementCopyAttributeValue(el, kAXExtrasMenuBarAttribute, &v)` | 取该 App 的状态项容器 | 正常 |
| `…kAXChildrenAttribute` | 取容器里的状态项列表 | 正常 |
| `…kAXRoleAttribute` | 取角色（判断是不是菜单栏项） | 正常 |
| `…kAXPositionAttribute` / `kAXSizeAttribute` | 读位置 / 尺寸 | 折叠项坐标是**假的**（实测全报 1155~1175） |
| `AXValueGetValue(_:_:_:)` | 从 `AXValue` 取 `CGPoint` / `CGSize` | 正常 |
| `AXValueCreate(_:_:)` | 造 `AXValue` | 仅用于被禁用的写入实验 |
| `AXUIElementIsAttributeSettable(el, kAXPositionAttribute, &ok)` | 探测属性可写 | **false** |
| `AXUIElementSetAttributeValue(el, kAXPositionAttribute, v)` | 写别人状态项位置 | **-25200；只改 AX 缓存，真实图标不动 → 禁用** |
| `AXUIElementSetAttributeValue(el, kAXSizeAttribute, v)` | 改别人状态项宽度 | **-25200；`settable=false`；相邻项位置未变 → 真实宽度没变，只写脏缓存 → 禁用** |
| `AXUIElementPerformAction(el, kAXPressAction)` | 按下别人状态项（弹出它自己的菜单） | 可用，但不能移动它 |
| `AXUIElementSetMessagingTimeout(el, 0.5)` | 设单次 AX 调用超时 | 扫描防卡死 |
| `AXError` 码 | `0` 成功 / `-25200` 失败 / `-25204` 无法完成 / `-25205` 属性不支持 | 记录日志用 |

## 4. 视口与屏幕几何

| 函数 / 属性 | 一句话作用 | 实测 |
|---|---|---|
| `NSScreen.main` / `NSScreen.screens` | 主屏 / 所有屏 | 2056×1329 |
| `NSScreen.frame` / `.visibleFrame` | 整屏 / 去掉菜单栏与 Dock | frame 高 1329，visible 1289 |
| `NSScreen.safeAreaInsets` | 刘海安全区 | top = 38 |
| `NSScreen.auxiliaryTopLeftArea` | 刘海左侧可用条 | `(0, 1291, 918, 38)` |
| `NSScreen.auxiliaryTopRightArea` | 刘海右侧可用条 | `(1138, 1291, 918, 38)` → **视口左缘 = 1138** |
| `NSApplication.didChangeScreenParametersNotification` | 屏幕参数变化通知 | 重算视口 |
| `NSWorkspace.shared.desktopImageURL(for:)` | 取壁纸文件 URL | 判断菜单栏深浅 |

## 5. 图标与绘制

| 函数 / 属性 | 一句话作用 | 备注 |
|---|---|---|
| `NSRunningApplication.icon` | 取运行中 App 的图标 | 备用 |
| `NSWorkspace.shared.icon(forFile:)` | 按路径取 App 图标 | 未启动的 App |
| `NSImage(size:flipped:drawingHandler:)` | 用绘制闭包造图 | 画带子 |
| `NSImage.SymbolConfiguration(pointSize:weight:)` | SF Symbol 尺寸 | 标识 13pt |
| `NSImage.SymbolConfiguration.init(paletteColors:)` + `.applying(_:)` | 给模板图上色 | **模板图 `draw` 不吃 `NSColor.set()`** |
| `NSImage.draw(in:)` / `draw(in:from:operation:fraction:)` | 画图 | |
| `NSImage.isTemplate` | 模板标志 | 设 false 保留颜色 |
| `CGImage.cropping(to:)` | 裁剪位图 | 取壁纸顶部 3% |
| `CGContext.draw(_:in:)` | 把裁剪图缩成 1×1 取亮度 | 判断深浅 |
| `NSColorSpace.deviceRGB` / `CGImageAlphaInfo.premultipliedLast` | 建位图上下文参数 | |

## 6. 应用发现与启动

| 函数 / 属性 | 一句话作用 |
|---|---|
| `NSWorkspace.shared.runningApplications` | 所有运行中的 App |
| `NSRunningApplication.bundleIdentifier` / `.localizedName` / `.processIdentifier` / `.activationPolicy` / `.icon` | 基本身份信息 |
| `NSRunningApplication.activate(options:)` | 把该 App 切到前台 |
| `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` | 找 App 的磁盘位置 |
| `NSWorkspace.shared.openApplication(at:configuration:completionHandler:)` | 启动 App |
| `NSWorkspace.didLaunchApplicationNotification` / `didTerminateApplicationNotification` | App 增减通知（触发重排） |

## 7. 事件与通知

| 函数 / 常量 | 一句话作用 |
|---|---|
| `NSWorkspace.shared.notificationCenter.addObserver(forName:object:queue:using:)` | 监听 `NSWorkspaceDidWakeNotification`（唤醒重排） |
| `NotificationCenter.default.addObserver(_:selector:name:object:)` | 监听屏幕/AX 变化 |
| `NSApplication.shared.setActivationPolicy(.accessory)` | 不在 Dock 显示 |
| `NSApp.activate(ignoringOtherApps:)` | 让面板获得焦点 |

## 8. 并发与定时

| 函数 | 一句话作用 |
|---|---|
| `DispatchQueue(label:)` | 建串行队列（排布/拖拽专用，避免冻结 UI） |
| `DispatchQueue.asyncAfter(deadline:execute:)` | 延时执行下一步 |
| `DispatchQueue.main.async` | 回主线程改 UI |
| `NSLock` | 保护 AX 扫描缓存 |
| `CFAbsoluteTimeGetCurrent()` | 打点计时（日志耗时） |
| `Timer.scheduledTimer(withTimeInterval:repeats:block:)` | 8s 巡检 / 60s 退避 |

## 9. 配置与持久化

| 函数 | 一句话作用 |
|---|---|
| `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` | 配置目录 |
| `JSONDecoder().decode(_:from:)` / `JSONEncoder().encode(_:)` | 配置结构体 ↔ JSON |
| `Data(contentsOf:)` / `Data.write(to:)` | 读/写文件 |
| `UserDefaults.standard` | 少量开关（备用） |

## 10. 设置窗口 UI

| 函数 / 属性 | 一句话作用 | 用途 |
|---|---|---|
| `NSWindow(styleMask:backing:defer:)` | 建窗口 | 设置窗 |
| `NSWindow.titlebarAppearsTransparent` / `isMovableByWindowBackground` | 标题栏透明 / 整窗可拖 | 外观 |
| `NSStackView` / `NSGridView` / `NSBox` / `NSScrollView` | 布局容器 | 左右两栏 |
| `NSButton` / `NSSegmentedControl` / `NSPopUpButton` / `NSTextField(labelWithString:)` | 常用控件 | 关闭时操作下拉、导航 |
| `NSView.wantsLayer` + `layer?.borderWidth` / `.borderColor` / `.cornerRadius` | 给视图加边框/圆角 | **2.4 显示应用栏边框** |
| `NSDraggingSource` / `NSDraggingDestination` | 拖拽源/目标协议 | 图标拖动排序 |
| `NSDraggingItem` / `NSPasteboard` / `NSPasteboardItem` | 拖拽载荷 | 传递 bundleID |
| `NSAnimationContext.runAnimationGroup(_:completionHandler:)` + `animator()` | 动画事务 | 0.12s 重排动画 |
| `NSTrackingArea` | 悬停区域 | 悬停高亮 |
| `NSImageView.imageScaling` | 图像缩放模式 | 图标等比 |

## 11. 登录项（开机自启）

| 函数 | 一句话作用 |
|---|---|
| `SMAppService.mainApp` | 代表主 App 的登录项对象 |
| `SMAppService.mainApp.register()` / `.unregister()` | 注册 / 取消开机自启（macOS 13+） |
| `SMAppService.mainApp.status` | 当前状态（`.enabled` / `.requiresApproval` …） |
| `SMAppService.openSystemSettingsLoginItems()` | 跳到系统设置里的登录项页 |

## 12. 明确「不可用 / 别再用」（记录在案）

| 尝试 | 结论 |
|---|---|
| `CGWindowListCopyWindowInfo` 取 `kCGWindowLayer == 25` 的状态项窗口 | macOS 27 已无独立窗口（实测返回空），菜单栏项被合并为一个 WindowServer 窗口 |
| `AXUIElementSetAttributeValue(kAXPositionAttribute)` 移动别人项 | 不可写（`settable = false`，`-25200`），只会写脏 AX 缓存 |
| 任何 `NSStatusBar` / `NSStatusItem` 的排序、位置、索引接口 | SDK 中不存在（`NSStatusBar` 仅 5 个成员，`NSStatusItem` 仅长度/可见/名称等） |
| 读别人 App 的 `NSStatusItem Preferred Position` 偏好来改顺序 | 需目标 App 重启才生效，macOS 27 未验证 |
