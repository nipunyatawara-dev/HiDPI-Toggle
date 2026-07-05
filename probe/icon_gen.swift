// Builds a clean macOS .iconset from the AI-generated icon art:
// finds the squircle's bounding box (ignoring the baked-in checkerboard
// background), crops it, applies a rounded-rect alpha mask, centers it on a
// transparent 1024x1024 canvas with Apple's standard margins, and writes
// all ten iconset PNG sizes.

import AppKit
import CoreGraphics
import UniformTypeIdentifiers

let sourcePath = CommandLine.arguments[1]
let outputDir = CommandLine.arguments[2]

guard let source = NSImage(contentsOfFile: sourcePath),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("cannot load \(sourcePath)")
}

let width = cg.width
let height = cg.height
guard let data = cg.dataProvider?.data as Data? else { fatalError("no pixel data") }
let bytesPerRow = cg.bytesPerRow
let bpp = cg.bitsPerPixel / 8

// Bounding box of "non-checkerboard" pixels. The checkerboard is light and
// unsaturated; the squircle is a saturated dark blue.
var minX = width, minY = height, maxX = 0, maxY = 0
data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
    let ptr = raw.bindMemory(to: UInt8.self).baseAddress!
    for y in 0..<height {
        for x in 0..<width {
            let p = ptr + y * bytesPerRow + x * bpp
            let r = Int(p[0]), g = Int(p[1]), b = Int(p[2])
            let isLightGray = r > 170 && g > 170 && b > 170
                && abs(r - g) < 25 && abs(g - b) < 25
            if !isLightGray {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
}
let bbox = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
print("squircle bbox: \(bbox) in \(width)x\(height)")

guard let cropped = cg.cropping(to: bbox) else { fatalError("crop failed") }

func renderIcon(size: Int) -> CGImage {
    let canvas = CGFloat(size)
    // Apple icon grid: artwork occupies ~824/1024 of the canvas.
    let art = canvas * 824.0 / 1024.0
    let margin = (canvas - art) / 2
    let corner = art * 185.0 / 824.0

    let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let rect = CGRect(x: margin, y: margin, width: art, height: art)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(cropped, in: rect)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(renderIcon(size: base), to: "\(outputDir)/icon_\(base)x\(base).png")
    writePNG(renderIcon(size: base * 2), to: "\(outputDir)/icon_\(base)x\(base)@2x.png")
}
print("iconset written to \(outputDir)")
