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
    NSGradient(colors: [NSColor(calibratedRed: 0.05, green: 0.77, blue: 0.52, alpha: 1),
                       NSColor(calibratedRed: 0.07, green: 0.30, blue: 0.66, alpha: 1)])!
        .draw(in: tile, angle: -65)

    // One bold handset silhouette stays legible in the Dock and at 16 px.
    // The two rounded earpieces and curved grip are original geometric artwork.
    let handset = NSBezierPath()
    handset.move(to: NSPoint(x: 310, y: 800))
    handset.curve(to: NSPoint(x: 204, y: 714), controlPoint1: NSPoint(x: 244, y: 832), controlPoint2: NSPoint(x: 184, y: 788))
    handset.curve(to: NSPoint(x: 710, y: 204), controlPoint1: NSPoint(x: 260, y: 466), controlPoint2: NSPoint(x: 464, y: 260))
    handset.curve(to: NSPoint(x: 800, y: 310), controlPoint1: NSPoint(x: 784, y: 184), controlPoint2: NSPoint(x: 834, y: 244))
    handset.line(to: NSPoint(x: 760, y: 400))
    handset.curve(to: NSPoint(x: 707, y: 422), controlPoint1: NSPoint(x: 750, y: 426), controlPoint2: NSPoint(x: 730, y: 434))
    handset.line(to: NSPoint(x: 615, y: 379))
    handset.curve(to: NSPoint(x: 570, y: 386), controlPoint1: NSPoint(x: 597, y: 371), controlPoint2: NSPoint(x: 583, y: 374))
    handset.curve(to: NSPoint(x: 386, y: 570), controlPoint1: NSPoint(x: 490, y: 426), controlPoint2: NSPoint(x: 426, y: 490))
    handset.curve(to: NSPoint(x: 379, y: 615), controlPoint1: NSPoint(x: 374, y: 583), controlPoint2: NSPoint(x: 371, y: 597))
    handset.line(to: NSPoint(x: 422, y: 707))
    handset.curve(to: NSPoint(x: 400, y: 760), controlPoint1: NSPoint(x: 434, y: 730), controlPoint2: NSPoint(x: 426, y: 750))
    handset.close()
    NSColor.white.setFill()
    handset.fill()
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
}
