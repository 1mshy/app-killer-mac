import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        // An explicit bitmap context works on CI without a display and fixes
        // the pixel dimensions independently of the host's Retina scale.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let p = CGFloat(pixels)
        NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.19, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.08, y: p * 0.08, width: p * 0.84, height: p * 0.84), xRadius: p * 0.20, yRadius: p * 0.20).fill()
        let ring = NSBezierPath(ovalIn: NSRect(x: p * 0.26, y: p * 0.26, width: p * 0.48, height: p * 0.48))
        ring.lineWidth = p * 0.054
        NSColor(calibratedRed: 1, green: 0.31, blue: 0.30, alpha: 1).setStroke()
        ring.stroke()
        NSColor(calibratedRed: 1, green: 0.31, blue: 0.30, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.404, y: p * 0.404, width: p * 0.192, height: p * 0.192), xRadius: p * 0.026, yRadius: p * 0.026).fill()
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try data.write(to: output.appendingPathComponent(name))
    }
}
