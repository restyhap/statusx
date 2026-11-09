#!/usr/bin/env python3
"""校验 icns 结构：条目长度含 8 字节头，最后一块必须刚好结束。

用法：check-icns.py <file.icns>   （通过退出码判断，0 = 合法）
"""
import sys

# icns 里除图标外的元数据条目（iconutil 会写 info）
KNOWN_OTHER = {b"info", b"TOC ", b"icnV", b"name"}

def check(path):
    d = open(path, "rb").read()
    if d[:4] != b"icns":
        return f"魔数不是 icns: {d[:4]!r}"
    declared = int.from_bytes(d[4:8], "big")
    if declared != len(d):
        return f"声明大小 {declared} != 实际 {len(d)}"
    i, entries = 8, []
    while i + 8 <= len(d):
        typ = d[i:i+4]
        size = int.from_bytes(d[i+4:i+8], "big")
        if size < 8 or i + size > len(d) or not (typ.startswith(b"ic") or typ in KNOWN_OTHER):
            return f"条目损坏 @{i}: type={typ!r} size={size}"
        entries.append(typ.decode("latin1"))
        i += size                      # 关键：size 含 8 字节头
    if i != len(d):
        return f"尾部多余 {len(d) - i} 字节"
    if not entries:
        return "没有任何条目"
    return None, entries

if __name__ == "__main__":
    r = check(sys.argv[1])
    if isinstance(r, str):
        print(f"❌ {sys.argv[1]}: {r}")
        sys.exit(1)
    print(f"✅ icns 合法：{len(r[1])} 个条目（{', '.join(r[1])}）")
