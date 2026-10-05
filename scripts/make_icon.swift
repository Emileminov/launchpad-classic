import AppKit

// Рисует значок: серебристая плитка с ракетой, как у старого Launchpad.
let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.white.setFill(); path.fill()
ctx.restoreGState()
path.addClip()
let grad = NSGradient(colors: [NSColor(white: 0.97, alpha: 1), NSColor(white: 0.62, alpha: 1)])!
grad.draw(in: tile, angle: -90)

// ракета (рисуем вертикально, затем поворачиваем на 45°)
ctx.translateBy(x: S/2, y: S/2)
ctx.rotate(by: .pi / 4)
let body = NSBezierPath()
body.move(to: CGPoint(x: 0, y: 300))
body.curve(to: CGPoint(x: 95, y: 40), controlPoint1: CGPoint(x: 80, y: 220), controlPoint2: CGPoint(x: 95, y: 130))
body.line(to: CGPoint(x: 95, y: -150))
body.line(to: CGPoint(x: -95, y: -150))
body.line(to: CGPoint(x: -95, y: 40))
body.curve(to: CGPoint(x: 0, y: 300), controlPoint1: CGPoint(x: -95, y: 130), controlPoint2: CGPoint(x: -80, y: 220))
body.close()
NSGradient(colors: [NSColor(white: 1, alpha: 1), NSColor(white: 0.78, alpha: 1)])!.draw(in: body, angle: 0)
NSColor(white: 0.45, alpha: 1).setStroke(); body.lineWidth = 5; body.stroke()

func fin(_ sign: CGFloat) {
    let f = NSBezierPath()
    f.move(to: CGPoint(x: sign * 95, y: 20))
    f.line(to: CGPoint(x: sign * 190, y: -150))
    f.line(to: CGPoint(x: sign * 95, y: -110))
    f.close()
    NSColor(red: 0.92, green: 0.22, blue: 0.2, alpha: 1).setFill(); f.fill()
}
fin(1); fin(-1)
let nose = NSBezierPath()
nose.move(to: CGPoint(x: 0, y: 300))
nose.curve(to: CGPoint(x: 70, y: 160), controlPoint1: CGPoint(x: 45, y: 255), controlPoint2: CGPoint(x: 62, y: 205))
nose.line(to: CGPoint(x: -70, y: 160))
nose.curve(to: CGPoint(x: 0, y: 300), controlPoint1: CGPoint(x: -62, y: 205), controlPoint2: CGPoint(x: -45, y: 255))
NSColor(red: 0.92, green: 0.22, blue: 0.2, alpha: 1).setFill(); nose.fill()
let win = NSBezierPath(ovalIn: CGRect(x: -48, y: 60, width: 96, height: 96))
NSColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 1).setFill(); win.fill()
NSColor(white: 0.4, alpha: 1).setStroke(); win.lineWidth = 8; win.stroke()
let flame = NSBezierPath()
flame.move(to: CGPoint(x: -60, y: -150)); flame.line(to: CGPoint(x: 0, y: -290)); flame.line(to: CGPoint(x: 60, y: -150)); flame.close()
NSGradient(colors: [NSColor.yellow, NSColor.orange])!.draw(in: flame, angle: -90)
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
