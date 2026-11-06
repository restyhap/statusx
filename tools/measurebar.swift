import Cocoa

// 用像素测量菜单栏项的真实横向范围（不依赖 AX，避免被假坐标/假宽度骗）
// 用法: measurebar <png> <x0> <x1>
let args = CommandLine.arguments
guard args.count >= 4, let img = NSImage(contentsOfFile: args[1]),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let x0 = Int(args[2]), let x1 = Int(args[3]) else { exit(1) }
let w = cg.width, h = cg.height
var data = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

func px(_ x: Int, _ y: Int) -> (Int, Int, Int) {
    let i = (y * w + x) * 4
    return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
}
// 每列：与该列顶部像素（背景）比较，差超过阈值算"有内容"
var cols: [Bool] = []
for x in max(0, x0)..<min(w, x1) {
    let bg = px(x, 1)
    var hit = false
    for y in 2..<h {
        let p = px(x, y)
        let d = abs(p.0 - bg.0) + abs(p.1 - bg.1) + abs(p.2 - bg.2)
        if d > 90 { hit = true; break }
    }
    cols.append(hit)
}
// 输出连续段（换算成点：2x 屏除以 2）
var run: Int?
for (i, on) in cols.enumerated() {
    if on, run == nil { run = i }
    if !on, let s = run {
        let x = Double(max(0, x0) + s) / 2, wid = Double(i - s) / 2
        if wid > 4 { print(String(format: "x=%.0f w=%.0f", x, wid)) }
        run = nil
    }
}
if let s = run {
    let x = Double(max(0, x0) + s) / 2, wid = Double(cols.count - s) / 2
    if wid > 4 { print(String(format: "x=%.0f w=%.0f", x, wid)) }
}
