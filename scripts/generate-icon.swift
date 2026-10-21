// Original Simple Dialler artwork. Drawn from geometric paths; no font or symbol assets.
import AppKit
import CoreGraphics
import Foundation

let out = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let sizes = [("icon_16x16.png",16),("icon_16x16@2x.png",32),("icon_32x32.png",32),("icon_32x32@2x.png",64),("icon_128x128.png",128),("icon_128x128@2x.png",256),("icon_256x256.png",256),("icon_256x256@2x.png",512),("icon_512x512.png",512),("icon_512x512@2x.png",1024)]
for (name, size) in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let tile = NSBezierPath(roundedRect: CGRect(x: 48, y: 48, width: 928, height: 928),
                            xRadius: 218, yRadius: 218)
    NSGradient(colors: [NSColor(calibratedRed: 0.05, green: 0.74, blue: 0.71, alpha: 1),
                       NSColor(calibratedRed: 0.07, green: 0.30, blue: 0.66, alpha: 1)])!
        .draw(in: tile, angle: -65)

    // A circular dial surrounds six offset keypad apertures, with a pointer at its foot.
    // The open ring gives the mark a recognisable silhouette even at small sizes.
    let ring = NSBezierPath()
    ring.appendArc(withCenter: NSPoint(x: 512, y: 536), radius: 278,
                   startAngle: -50, endAngle: 230, clockwise: false)
    ring.lineWidth = 68
    ring.lineCapStyle = .round
    NSColor.white.setStroke()
    ring.stroke()
    for y in [CGFloat(488), 624] {
        for x in [CGFloat(390), 512, 634] {
            NSColor.white.setFill()
            NSBezierPath(ovalIn: CGRect(x: x - 33, y: y - 33, width: 66, height: 66)).fill()
        }
    }
    let pointer = NSBezierPath(roundedRect: CGRect(x: 478, y: 220, width: 68, height: 164),
                               xRadius: 34, yRadius: 34)
    NSColor.white.setFill()
    pointer.fill()
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
}
