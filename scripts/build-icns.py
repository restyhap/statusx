#!/usr/bin/env python3
"""由 AppIcon.svg 生成合法的 AppIcon.icns（不依赖 iconutil 的 bug）。

icns 格式：'icns' + 4 字节总大小 + 若干(4 字节类型 + 4 字节数据大小 + 数据)。
图标数据用 PNG 包装，类型码沿用 Apple convention：
    16  32  64  128  256  512  1024
    icp4 icp5 icp6 icp7 icp8 icp9 ic10
另外各放一份 @2x 重复（ic11..ic14），兼容旧版 Finder。
"""
import os, struct, subprocess, sys

SVG = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Assets/icon/AppIcon.svg")
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Packaging/AppIcon.icns")
SIZES = [16, 32, 64, 128, 256, 512, 1024]
TYP = {16: "icp4", 32: "icp5", 64: "icp6", 128: "icp7", 256: "icp8", 512: "icp9", 1024: "ic10"}
ALT = {32: "ic11", 64: "ic12", 256: "ic13", 512: "ic14"}


def rsvg(width, dest):
    subprocess.run(["rsvg-convert", "-w", str(width), "-h", str(width), SVG, "-o", dest], check=True)


def main():
    tmp = os.path.splitext(OUT)[0] + ".iconset"
    os.makedirs(tmp, exist_ok=True)
    entries = b""
    for size in SIZES:
        png = os.path.join(tmp, f"icon_{size}x{size}.png")
        rsvg(size, png)
        data = open(png, "rb").read()
        entries += TYP[size].encode() + struct.pack(">I", len(data)) + data
        if size in ALT:
            entries += ALT[size].encode() + struct.pack(">I", len(data)) + data
    body = b"icns" + struct.pack(">I", 8 + len(entries)) + entries
    with open(OUT, "wb") as f:
        f.write(body)
    print(f"已生成 {OUT}（{len(body)} 字节，{len(SIZES) + len(ALT)} 个条目）")


if __name__ == "__main__":
    main()
