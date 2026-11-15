// Generates Android adaptive-icon foreground bitmaps from the Icon Composer source.
//
//   swift android/scripts/make-icons.swift
//
// The background is a vector gradient drawable (no bitmap needed), so only the
// foreground layer is rendered here: the tree centred on a transparent 108dp
// canvas, scaled to sit inside the 72dp safe zone.

import AppKit
import Foundation

let repo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()   // android/scripts
    .deletingLastPathComponent()   // android
    .deletingLastPathComponent()   // repo root

let source = repo
    .appendingPathComponent("macos/Resources/Zree.icon/Assets/知識の木ネットワークアイコン.png")
let resDir = repo.appendingPathComponent("android/app/src/main/res")

guard let image = NSImage(contentsOf: source) else {
    FileHandle.standardError.write("cannot read \(source.path)\n".data(using: .utf8)!)
    exit(1)
}

// density suffix -> pixels per dp
let densities: [(String, CGFloat)] = [
    ("mdpi", 1.0), ("hdpi", 1.5), ("xhdpi", 2.0), ("xxhdpi", 3.0), ("xxxhdpi", 4.0),
]

let canvasDp: CGFloat = 108
// icon.json scales the layer to 0.8, but inside Android's 108dp canvas that made
// the tree read too large next to other launcher icons; 0.64 of the canvas puts it
// at roughly 80% of that, comfortably inside the 72dp safe zone.
let artDp: CGFloat = canvasDp * 0.64

for (suffix, scale) in densities {
    let px = Int((canvasDp * scale).rounded())
    let art = artDp * scale

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { continue }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(x: (CGFloat(px) - art) / 2, y: (CGFloat(px) - art) / 2, width: art, height: art)
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()

    let dir = resDir.appendingPathComponent("mipmap-\(suffix)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let out = dir.appendingPathComponent("ic_launcher_foreground.png")
    try? rep.representation(using: .png, properties: [:])?.write(to: out)
    print("\(out.lastPathComponent) \(px)x\(px) -> \(dir.lastPathComponent)")
}
