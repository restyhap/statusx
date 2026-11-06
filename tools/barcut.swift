import Cocoa

// 用法: barcut <png> [起始x] [缩放]  —— 找出菜单栏上真正画出来的图标列区间
// 用途：折叠项的 AX 坐标是系统伪造的假帧，只有像素可信。
let args = CommandLine.arguments
guard args.count > 1, let img = NSImage(contentsOfFile: args[1]),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("读不到图片"); exit(1)
}
let startX = args.count > 2 ? Double(args[2]) ?? 0 : 0
let scale = args.count > 3 ? Double(args[3]) ?? 2 : 2

let w = cg.width, h = cg.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

var hits = [Bool](repeating: false, count: w)
let y0 = 4, y1 = min(h - 6, 36)
for x in 0..<w {
    var n = 0
    for y in y0..<y1 {
        let i = (y * w + x) * 4
        let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
        if r > 150 && g > 150 && b > 150 { n += 1 }
    }
    hits[x] = n >= 3
}

var clusters: [(Int, Int)] = []
var start = -1
for x in 0..<w {
    if hits[x] {
        if start < 0 { start = x }
    } else if start >= 0 {
        if x - start >= 3 { clusters.append((start, x - 1)) }
        start = -1
    }
}
if start >= 0 { clusters.append((start, w - 1)) }

for (a, b) in clusters {
    let sa = startX + Double(a) / scale
    let sb = startX + Double(b) / scale
    print(String(format: "  %4d – %4d   宽 %3d", Int(sa), Int(sb), Int(sb - sa) + 1))
}
