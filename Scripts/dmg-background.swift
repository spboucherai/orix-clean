// ORIX Clean — Scripts/dmg-background.swift
// Description: Draws the disk-image background (660×420 pt at 2x): brand gradient, title and a drag arrow.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let w = 1320, h = 840
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: 660, height: 420)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGradient(colors: [NSColor(srgbRed: 0.07, green: 0.09, blue: 0.17, alpha: 1), NSColor(srgbRed: 0.03, green: 0.04, blue: 0.09, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: 660, height: 420), angle: -90)
NSGradient(colors: [NSColor(srgbRed: 0.18, green: 0.83, blue: 0.75, alpha: 0.22), .clear])!
    .draw(fromCenter: NSPoint(x: 330, y: 215), radius: 0, toCenter: NSPoint(x: 330, y: 215), radius: 330, options: [])
func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ alpha: CGFloat, y: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: NSColor(white: 1, alpha: alpha), .paragraphStyle: p])
        .draw(in: NSRect(x: 0, y: y, width: 660, height: size * 1.5))
}
text("ORIX Clean", 26, .bold, 0.96, y: 345)
text("Reclaim Space. Keep Control.", 13, .regular, 0.6, y: 322)
text("Drag ORIX Clean to the Applications folder", 13, .medium, 0.75, y: 62)
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 285, y: 215)); arrow.line(to: NSPoint(x: 372, y: 215))
arrow.move(to: NSPoint(x: 358, y: 229)); arrow.line(to: NSPoint(x: 374, y: 215)); arrow.line(to: NSPoint(x: 358, y: 201))
arrow.lineWidth = 5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
NSColor(srgbRed: 0.37, green: 0.92, blue: 0.83, alpha: 0.9).setStroke(); arrow.stroke()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
