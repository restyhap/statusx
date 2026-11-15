#!/usr/bin/env python3
"""归一化复现脚本：夜色（深色外观）下弹窗看不清的成因。

两个子问题，分别给出可复现的判定：
  A. 卡片底色与文字色的对比度
  B. 带子宽度上限未封顶时，真实渲染是否能超过 310

只做颜色推导 + 源码静态检查，不启动 App。
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PANEL = os.path.join(ROOT, "Sources", "StatusX", "Panel.swift")
BAR = os.path.join(ROOT, "Sources", "StatusX", "BarStrip.swift")
APP = os.path.join(ROOT, "Sources", "StatusX", "AppController.swift")
CFG = os.path.join(ROOT, "Sources", "StatusX", "Config.swift")
PLACER = os.path.join(ROOT, "Sources", "StatusX", "Placer.swift")


def src(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()


# ------------------------------------------------------------------
# A. 夜色模式对比度
# ------------------------------------------------------------------


def rel_lum(rgb: tuple[float, float, float]) -> float:
    def ch(c: float) -> float:
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (ch(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    la, lb = rel_lum(a), rel_lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


# 深色外观：AppKit labelColor 解析为近白；white 模式的 GradientBackground 停在 #E3F2FA..纯白
DARK_LABEL = (0.945, 0.945, 0.945)
DARK_CONTROL_BG = (0.165, 0.165, 0.173)  # controlBackgroundColor 深色 ≈ #2A2A2C
HARD_WHITE = (1.0, 1.0, 1.0)
POPOVER_DARK = (0.12, 0.12, 0.14)  # popover 实色底（深色）总量级近似

cases = [
    ("旧：卡片底 #FFFFFF + labelColor(夜色)", HARD_WHITE, DARK_LABEL),
    (
        "新：卡片底 controlBackgroundColor + labelColor(夜色)",
        DARK_CONTROL_BG,
        DARK_LABEL,
    ),
    ("参考：popover 深色底 + labelColor(夜色)", POPOVER_DARK, DARK_LABEL),
]

print("== A. 深色外观对比度（WCAG 阈值 4.5 正文 / 3.0 大字）==")
for name, bg, fg in cases:
    print(f"  {contrast(fg, bg):5.2f}  {name}")

old_contrast = contrast(DARK_LABEL, HARD_WHITE)
new_contrast = contrast(DARK_LABEL, DARK_CONTROL_BG)

panel_src = src(PANEL)

hard_white = re.search(
    r"layer\?\.backgroundColor\s*=\s*NSColor\.white\.cgColor", panel_src
)
adapted = re.search(
    r"layer\?\.backgroundColor\s*=\s*NSColor\.controlBackgroundColor\.cgColor",
    panel_src,
)
refresh = re.search(r"refreshCardColors|func refreshCardColor", panel_src)

print()
if hard_white:
    print("  [A] 源码：CardView 仍在写死 NSColor.white —— 夜色下白底白字")
elif adapted and refresh:
    print(
        "  [A] 源码：CardView 底色已跟外观走（controlBackgroundColor + refreshCardColor）"
    )
elif adapted:
    print("  [A] 源码：底色已跟外观走，但 refresh 开关/重建钩子缺失")
else:
    print("  [A] 源码：未找到卡片底色赋值（需人工确认）")

a_ok = adapted is not None and hard_white is None and new_contrast >= 4.5
print(
    f"  旧对比度 {old_contrast:.2f}（不可读）→ 新对比度 {new_contrast:.2f}（{'通过' if new_contrast >= 4.5 else '仍不足'}）"
)

# ------------------------------------------------------------------
# B. 带子宽度：310 硬上限 + 启动校准后固定
# ------------------------------------------------------------------

print()
print("== B. 带子宽度（310 硬上限，启动校准一次后固定）==")

app_src = src(APP)
cfg_src = src(CFG)
placer_src = src(PLACER)

max_width = re.search(r"static\s+let\s+maxWidth:\s*CGFloat\s*=\s*310", placer_src)
probe = re.search(r"static\s+let\s+probeWidth:\s*CGFloat\s*=\s*18", placer_src)
binary = re.search(r"func\s+search\(low:\s*CGFloat,\s*high:\s*CGFloat", placer_src)
ax_visible = re.search(r"MBar\.own\(\)\s*!=\s*nil", placer_src)
ignores_config = re.search(r"func\s+apply\(_ config: Config\)\s*\{\}", placer_src)
capped = re.search(r"let\s+capped\s*=\s*min\(Self\.maxWidth", placer_src)
cfg_clamped = re.search(r"bandWidth\s*=\s*min\(310", cfg_src)
# renderStrip 里绝不再写 item.length（宽度只由 Placer 定）
render_write = re.search(r"func\s+renderStrip[\s\S]{0,2000}?item\.length\s*=", app_src)

for name, hit in [
    ("Placer.maxWidth = 310（硬上限）", max_width),
    ("Placer.probeWidth = 18（先最窄落地）", probe),
    ("二分探测可用槽位（search(low:high:)）", binary),
    ("可见性以 AX extras 为准（MBar.own()）", ax_visible),
    ("Placer.apply 不再理会 bandWidth/autoWidth", ignores_config),
    ("最终宽度 min(maxWidth, 探测值)", capped),
    ("Config 解码 bandWidth 后封顶 310", cfg_clamped),
    ("renderStrip 不写 item.length", None if render_write else True),
]:
    print(f"  {'有' if hit else '无'}  {name}")

b_ok = all(
    [
        max_width,
        probe,
        binary,
        ax_visible,
        ignores_config,
        capped,
        cfg_clamped,
        render_write is None,
    ]
)
print(
    f"  结论：{'宽度 ≤310 且启动校准后固定，不再随组件数/配置伸缩' if b_ok else '宽度仍可能超过 310 或随配置伸缩，需核对'}"
)

# ------------------------------------------------------------------
# C. 点击开关
# ------------------------------------------------------------------

print()
print("== C. 点带子显示 / 再点隐藏 ==")

monitor = re.search(r"startOutsideClickMonitor\(\)", app_src)
guard = re.search(r"now\s*-\s*lastPanelCloseAt\s*<\s*(\d+\.?\d*)", app_src)
point_check = re.search(r"locationInWindow", app_src)
local = re.search(r"addLocalMonitorForEvents", app_src)
toggle_close = re.search(r"closePanel\(\)", app_src)

print(
    f"  点击监听就位：{'是' if monitor else '否'}；局部监听：{'是' if local else '否'}"
)
if guard:
    print(f"  0.4s 抑制窗口仍在（{guard.group(1)}s）：快速二次点击会被吞")
else:
    print("  0.4s 抑制窗口已删：点击只靠 isVisible 关与开，且走局部监听")
print(f"  togglePanel 里关面板走 closePanel(): {'是' if toggle_close else '否'}")
print(
    f"  togglePanel 里点在带子上交给状态项 window.frame 判断: {'是' if point_check else '否'}"
)

c_ok = (
    guard is None
    and local is not None
    and toggle_close is not None
    and point_check is not None
)
print(
    f"  结论：{'点击开关不再被抑制窗口吞' if c_ok else '短时间内二次点击仍会被当成同一次点击吞掉'}"
)

print()
print("== 结论 ==")
print(f"  A 夜色可读性：{'已修复' if a_ok else '未修复'}")
print(f"  B 宽度上限/固定：{'已修复' if b_ok else '未修复/不确定'}")
print(f"  C 点击开关：{'已修复' if c_ok else '未修复'}")

sys.exit(0 if (a_ok and b_ok and c_ok) else 1)
