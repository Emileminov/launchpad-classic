import AppKit

// Значок как у Launchpad в macOS Big Sur … Sequoia: светлая плитка и сетка 3×3 цветных квадратов.
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.3).cgColor)
NSColor.white.setFill(); path.fill()
ctx.restoreGState()

ctx.saveGState()
path.addClip()
NSGradient(colors: [NSColor(white: 1.0, alpha: 1), NSColor(white: 0.84, alpha: 1)])!.draw(in: tile, angle: -90)
ctx.restoreGState()
NSColor(white: 1, alpha: 0.7).setStroke(); path.lineWidth = 3; path.stroke()

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(red: r/255, green: g/255, blue: b/255, alpha: 1) }
// (верх, низ) для каждой ячейки, слева направо, сверху вниз
let colors: [(NSColor, NSColor)] = [
    (rgb(120, 230, 100), rgb(40, 190, 60)),   // зелёный
    (rgb(255, 215, 80),  rgb(250, 175, 20)),  // жёлтый
    (rgb(255, 170, 60),  rgb(245, 120, 20)),  // оранжевый
    (rgb(255, 100, 90),  rgb(225, 40, 45)),   // красный
    (rgb(205, 210, 215), rgb(150, 155, 162)), // серый
    (rgb(255, 110, 150), rgb(235, 50, 100)),  // розовый
    (rgb(190, 110, 235), rgb(135, 60, 200)),  // фиолетовый
    (rgb(80, 175, 255),  rgb(20, 110, 235)),  // синий
    (rgb(100, 225, 190), rgb(40, 190, 150)),  // бирюзовый
]
let cell: CGFloat = 170, gap: CGFloat = 40
let total = cell * 3 + gap * 2
let x0 = S/2 - total/2, yTop = S/2 + total/2
for i in 0..<9 {
    let r = i / 3, c = i % 3
    let rect = CGRect(x: x0 + CGFloat(c) * (cell + gap), y: yTop - CGFloat(r + 1) * cell - CGFloat(r) * gap, width: cell, height: cell)
    let p = NSBezierPath(roundedRect: rect, xRadius: 42, yRadius: 42)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 9, color: NSColor.black.withAlphaComponent(0.22).cgColor)
    colors[i].1.setFill(); p.fill()
    ctx.restoreGState()
    ctx.saveGState(); p.addClip()
    NSGradient(colors: [colors[i].0, colors[i].1])!.draw(in: rect, angle: -90)
    ctx.restoreGState()
}
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
