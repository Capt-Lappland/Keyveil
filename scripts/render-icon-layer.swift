#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/keyveil-command-layer.png")
let size = 1024

guard
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
else {
    fatalError("Unable to create a bitmap context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let cg = context.cgContext
cg.clear(CGRect(x: 0, y: 0, width: size, height: size))
cg.setStrokeColor(NSColor(srgbRed: 197.0 / 255.0, green: 202.0 / 255.0, blue: 208.0 / 255.0, alpha: 1).cgColor)
cg.setLineWidth(82)
cg.setLineCap(.round)
cg.setLineJoin(.round)

let path = CGMutablePath()
path.move(to: CGPoint(x: 400, y: 400))
path.addLine(to: CGPoint(x: 288, y: 400))
path.addCurve(to: CGPoint(x: 160, y: 280), control1: CGPoint(x: 210, y: 400), control2: CGPoint(x: 160, y: 350))
path.addCurve(to: CGPoint(x: 280, y: 160), control1: CGPoint(x: 160, y: 210), control2: CGPoint(x: 210, y: 160))
path.addCurve(to: CGPoint(x: 400, y: 280), control1: CGPoint(x: 350, y: 160), control2: CGPoint(x: 400, y: 210))
path.addLine(to: CGPoint(x: 400, y: 744))
path.addCurve(to: CGPoint(x: 280, y: 864), control1: CGPoint(x: 400, y: 814), control2: CGPoint(x: 350, y: 864))
path.addCurve(to: CGPoint(x: 160, y: 744), control1: CGPoint(x: 210, y: 864), control2: CGPoint(x: 160, y: 814))
path.addCurve(to: CGPoint(x: 288, y: 624), control1: CGPoint(x: 160, y: 674), control2: CGPoint(x: 210, y: 624))
path.addLine(to: CGPoint(x: 736, y: 624))
path.addCurve(to: CGPoint(x: 864, y: 744), control1: CGPoint(x: 814, y: 624), control2: CGPoint(x: 864, y: 674))
path.addCurve(to: CGPoint(x: 744, y: 864), control1: CGPoint(x: 864, y: 814), control2: CGPoint(x: 814, y: 864))
path.addCurve(to: CGPoint(x: 624, y: 744), control1: CGPoint(x: 674, y: 864), control2: CGPoint(x: 624, y: 814))
path.addLine(to: CGPoint(x: 624, y: 280))
path.addCurve(to: CGPoint(x: 744, y: 160), control1: CGPoint(x: 624, y: 210), control2: CGPoint(x: 674, y: 160))
path.addCurve(to: CGPoint(x: 864, y: 280), control1: CGPoint(x: 814, y: 160), control2: CGPoint(x: 864, y: 210))
path.addCurve(to: CGPoint(x: 736, y: 400), control1: CGPoint(x: 864, y: 350), control2: CGPoint(x: 814, y: 400))
path.addLine(to: CGPoint(x: 400, y: 400))

cg.addPath(path)
cg.strokePath()
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode PNG")
}

try data.write(to: outputURL, options: .atomic)
