// Regenerate the checked-in 1x/2x artwork with macOS AppKit; no build-time renderer needed.
// swift qt/resources/dmg/render-background.swift qt/resources/dmg
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let width: CGFloat = 640, height: CGFloat = 400
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: alpha)
}
func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: height - top - h, width: w, height: h)
}
func text(_ value: String, top: CGFloat, size: CGFloat, weight: NSFont.Weight, ink: NSColor) {
    let string = NSAttributedString(string: value, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink
    ])
    let bounds = string.size()
    string.draw(at: NSPoint(x: (width - bounds.width) / 2, y: height - top - bounds.height))
}
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale,
        pixelsHigh: Int(height) * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    // bitmap.size already maps logical points to the requested pixel density.
    NSGradient(starting: color(244, 239, 255), ending: color(253, 252, 255))!
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

    text("安装 Woody", top: 34, size: 26, weight: .semibold, ink: color(43, 32, 67))
    text("将 Woody 拖到右侧 Applications 文件夹", top: 78, size: 14,
         weight: .regular, ink: color(107, 96, 127))

    for x: CGFloat in [98, 390] {
        let card = NSBezierPath(roundedRect: rect(x, 130, 152, 164), xRadius: 22, yRadius: 22)
        color(255, 255, 255, 0.86).setFill()
        card.fill()
        color(229, 220, 245).setStroke()
        card.lineWidth = 1
        card.stroke()
    }
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 292, y: height - 202))
    arrow.line(to: NSPoint(x: 348, y: height - 202))
    arrow.move(to: NSPoint(x: 336, y: height - 190))
    arrow.line(to: NSPoint(x: 348, y: height - 202))
    arrow.line(to: NSPoint(x: 336, y: height - 214))
    arrow.lineWidth = 4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    color(151, 111, 221).setStroke()
    arrow.stroke()

    color(229, 220, 245).setFill()
    rect(64, 330, 512, 1).fill()
    text("安装完成后，请推出此磁盘", top: 351, size: 12,
         weight: .regular, ink: color(126, 115, 144))
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "background.png" : "background@2x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}
