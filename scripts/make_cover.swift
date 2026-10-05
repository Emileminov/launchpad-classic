import AppKit
import CoreImage

// Обложка для публикации. Использование: swift scripts/make_cover.swift <выход.png> <иконка.png> [square]
// По умолчанию 1280×720, с режимом square — 1080×1080.
let out = CommandLine.arguments[1], iconPath = CommandLine.arguments[2]
let square = CommandLine.arguments.count > 3 && CommandLine.arguments[3] == "square"
let W: CGFloat = square ? 1080 : 1280, H: CGFloat = square ? 1080 : 720

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
func rr(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad, yRadius: rad) }
@discardableResult
func text(_ s: String, x: CGFloat, top: CGFloat, font: NSFont, color: NSColor, width: CGFloat? = nil, center: Bool = false) -> NSSize {
    let p = NSMutableParagraphStyle(); p.alignment = center ? .center : .left; p.lineSpacing = 4
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
    if let width {
        let r = str.boundingRect(with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin])
        str.draw(with: NSRect(x: x, y: H - top - r.height, width: width, height: r.height), options: [.usesLineFragmentOrigin])
        return r.size
    }
    let size = str.size()
    str.draw(at: NSPoint(x: x, y: H - top - size.height))
    return size
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// --- фон ---
c(0.055, 0.058, 0.070).setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
let canvas = NSRect(x: 0, y: 0, width: W, height: H)
NSGradient(colors: [c(0.35, 0.50, 1.0, 0.30), c(0.35, 0.50, 1.0, 0)])!.draw(in: canvas, relativeCenterPosition: NSPoint(x: 0.45, y: 0.0))
NSGradient(colors: [c(0.75, 0.40, 1.0, 0.10), c(0.75, 0.40, 1.0, 0)])!.draw(in: canvas, relativeCenterPosition: NSPoint(x: -0.85, y: 0.5))

// --- левая часть ---
let iconSide: CGFloat = square ? 96 : 84, iconTop: CGFloat = square ? 84 : 150
let lx: CGFloat = square ? 80 : 88
if let icon = NSImage(contentsOfFile: iconPath) { icon.draw(in: NSRect(x: lx, y: H - iconTop - iconSide, width: iconSide, height: iconSide)) }
let tf = NSFont.systemFont(ofSize: square ? 58 : 54, weight: .bold)
let th = NSAttributedString(string: "L", attributes: [.font: tf]).size().height
text("Launchpad Classic", x: lx + iconSide + 24, top: iconTop + (iconSide - th) / 2, font: tf, color: .white)
text("Тот самый Launchpad из прежних\nверсий macOS — снова с вами", x: lx, top: square ? 210 : 275, font: .systemFont(ofSize: square ? 32 : 31, weight: .regular), color: c(1, 1, 1, 0.72), width: square ? W - 2 * lx : nil)
var cx: CGFloat = lx
let chipTop: CGFloat = square ? 340 : 462
for label in ["Папки", "Поиск", "Перетаскивание", "Удаление"] {
    let f = NSFont.systemFont(ofSize: 17, weight: .semibold)
    let w = NSAttributedString(string: label, attributes: [.font: f]).size().width + 34
    let pill = rr(NSRect(x: cx, y: H - chipTop - 38, width: w, height: 38), 19)
    c(1, 1, 1, 0.10).setFill(); pill.fill(); c(1, 1, 1, 0.16).setStroke(); pill.lineWidth = 1; pill.stroke()
    text(label, x: cx + 17, top: chipTop + 8, font: f, color: c(1, 1, 1, 0.92))
    cx += w + 12
}
text("для macOS 14 и новее", x: lx, top: square ? 1010 : 598, font: .systemFont(ofSize: 18, weight: .medium), color: c(1, 1, 1, 0.5))

// --- макет экрана Launchpad (справа) ---
let screen = square ? NSRect(x: 130, y: 90, width: 820, height: 580) : NSRect(x: 690, y: 110, width: 520, height: 500)
let ctx = NSGraphicsContext.current!.cgContext
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: NSColor.black.withAlphaComponent(0.55).cgColor)
c(0.1, 0.1, 0.12).setFill(); rr(screen, 26).fill()
ctx.restoreGState()
ctx.saveGState()
rr(screen, 26).addClip()
// обои, размытые
let wpURL = NSWorkspace.shared.desktopImageURL(for: NSScreen.screens[0])
if let url = wpURL, let ci = CIImage(contentsOf: url) {
    let ext = ci.extent
    let scale = max(screen.width / ext.width, screen.height / ext.height) * 1.1
    let scaled = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let blurred = scaled.clampedToExtent().applyingGaussianBlur(sigma: 14).cropped(to: scaled.extent)
    let ciRep = NSCIImageRep(ciImage: blurred)
    let img = NSImage(size: ciRep.size); img.addRepresentation(ciRep)
    img.draw(in: NSRect(x: screen.minX - (ciRep.size.width - screen.width) / 2, y: screen.minY - (ciRep.size.height - screen.height) / 2,
                        width: ciRep.size.width, height: ciRep.size.height))
}
c(0, 0, 0, 0.26).setFill(); screen.fill()
// поиск
let sp = rr(NSRect(x: screen.midX - 70, y: screen.maxY - 56, width: 140, height: 26), 13)
c(1, 1, 1, 0.16).setFill(); sp.fill()
text("Поиск", x: screen.midX - 70, top: H - screen.maxY + 36, font: .systemFont(ofSize: 12), color: c(1, 1, 1, 0.6), width: 140, center: true)
// иконки
let names = ["Mail", "Messages", "Maps", "Photos", "FaceTime", "Calendar", "Contacts", "Reminders", "Notes", "Music", "TV", "Podcasts", "News", "Stocks", "Home", "Freeform", "Calculator", "Clock", "Weather", "Books"]
var paths: [(String, String)] = []
for n in names { for dir in ["/System/Applications", "/System/Cryptexes/App/System/Applications", "/Applications"] {
    let p = "\(dir)/\(n).app"; if FileManager.default.fileExists(atPath: p) { paths.append((n, p)); break } } }
let cols = 5, rows = 4, cell = square ? CGSize(width: 128, height: 104) : CGSize(width: 96, height: 98), isz: CGFloat = square ? 62 : 58
let gx = screen.minX + (screen.width - CGFloat(cols) * cell.width) / 2, gtop = H - screen.maxY + (square ? 78 : 82)
for (i, item) in paths.prefix(cols * rows).enumerated() {
    let col = i % cols, row = i / cols
    let x = gx + CGFloat(col) * cell.width + (cell.width - isz) / 2
    let top = gtop + CGFloat(row) * cell.height
    NSWorkspace.shared.icon(forFile: item.1).draw(in: NSRect(x: x, y: H - top - isz, width: isz, height: isz))
    text(item.0, x: gx + CGFloat(col) * cell.width, top: top + isz + 7, font: .systemFont(ofSize: 11), color: c(1, 1, 1, 0.9), width: cell.width, center: true)
}
// точки страниц
for k in 0..<3 {
    let d = NSBezierPath(ovalIn: NSRect(x: screen.midX - 21 + CGFloat(k) * 16, y: screen.minY + 22, width: 7, height: 7))
    c(1, 1, 1, k == 0 ? 0.95 : 0.35).setFill(); d.fill()
}
ctx.restoreGState()
c(1, 1, 1, 0.14).setStroke(); let b = rr(screen.insetBy(dx: 0.5, dy: 0.5), 26); b.lineWidth = 1; b.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
