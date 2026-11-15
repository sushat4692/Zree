// Pads the wordmark onto a transparent square canvas so Android's square splash
// icon slot does not squash it.
//
//   swift android/scripts/make-splash-logo.swift

import AppKit
import Foundation

let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

let src = repo.appendingPathComponent("docs/assets/zree-logo.png")
let out = repo.appendingPathComponent("android/app/src/main/res/drawable-nodpi/zree_splash_logo.png")

guard let image = NSImage(contentsOf: src) else {
    FileHandle.standardError.write("cannot read \(src.path)\n".data(using: .utf8)!)
    exit(1)
}

let side = 864.0
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

let ratio = image.size.height / image.size.width
let width = side * 0.86
let height = width * ratio
image.draw(in: NSRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height),
           from: .zero, operation: .sourceOver, fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

try? rep.representation(using: .png, properties: [:])?.write(to: out)
print("wrote \(out.lastPathComponent) \(Int(side))x\(Int(side))")
