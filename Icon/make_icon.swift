// Renders the 1024×1024 Headroom app icon (minimal flat sun on deep navy) to argv[1].
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let cs = CGColorSpace(name: CGColorSpace.displayP3)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func srgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let navy = srgb(0x0C1B33)
let sun = srgb(0xFAC775)

// macOS icon grid: 824 pt body inset by 100 pt.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

// Soft drop shadow, like system icons in the Dock.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: srgb(0x000000, 0.35))
ctx.addPath(shape); ctx.setFillColor(navy); ctx.fillPath()
ctx.restoreGState()

let center = CGPoint(x: 512, y: 512)
let unit = body.width / 160 // design grid: 160 × 160

// Disc
let r = 26 * unit
ctx.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
ctx.setFillColor(sun); ctx.fillPath()

// Eight short rays with round caps
ctx.setStrokeColor(sun)
ctx.setLineWidth(8 * unit)
ctx.setLineCap(.round)
for i in 0..<8 {
    let a = CGFloat(i) * .pi / 4
    let r0 = 46 * unit, r1 = 58 * unit
    ctx.move(to: CGPoint(x: center.x + cos(a) * r0, y: center.y + sin(a) * r0))
    ctx.addLine(to: CGPoint(x: center.x + cos(a) * r1, y: center.y + sin(a) * r1))
}
ctx.strokePath()

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
