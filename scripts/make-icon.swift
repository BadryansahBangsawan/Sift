#!/usr/bin/env swift
//
// make-icon.swift — regenerates the Sift app icon from vectors.
//
// Usage: swift scripts/make-icon.swift
//
// Spec (macOS Big Sur+ icon grid):
//   canvas          1024x1024, transparent outside the shape
//   body            824x824 centered, continuous-corner squircle (superellipse n=5,
//                   equivalent to a ~185 px rounded rect), ink #0D0F11
//   shadow          black 30%, y+10 px, blur 20 px, inside the canvas; both
//                   scale with the output size (1024 px reference) and are
//                   omitted at 32 px and below
//   mark            the Sift sieve: a brass #C9A227 grain resting on four
//                   light #F1EFEA sieve bars, two small grains falling through.
//                   Drawn on a 256-unit grid (same geometry as the logo kit) and
//                   scaled 3.2x onto the body. At 64 px and below the small cut
//                   is used: no falling grains, thicker bars, wider gaps.
//
// Every size is rasterized independently from the vectors, so nothing is
// downscaled from one master bitmap.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Paths

let scriptURL = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let iconSetDir = repoRoot.appendingPathComponent("Sift/Assets.xcassets/AppIcon.appiconset")
let docsIconURL = repoRoot.appendingPathComponent("docs/assets/icon.png")

// MARK: - Geometry (1024 px design space)

let canvas: CGFloat = 1024
let bodySize: CGFloat = 824
let bodyHalf = bodySize / 2
let bodyCenter = CGPoint(x: canvas / 2, y: canvas / 2)
let squircleExponent: CGFloat = 5 // continuous-corner approximation of r ≈ 185 px

// MARK: - Colors

func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

let inkColor = srgb(0x0D0F11)
let lightColor = srgb(0xF1EFEA)
let brassColor = srgb(0xC9A227)
let shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.3)

// MARK: - Mark (256-unit grid, y down, same geometry as the logo kit)

struct SieveMark {
    var bars: [CGRect]      // pill-shaped sieve bars
    var grains: [(CGPoint, CGFloat)]
    var nugget: (CGPoint, CGFloat)

    /// Full mark: four 44x22 bars 16 apart, a 46-radius nugget 8 above them.
    static let full: SieveMark = {
        let ybar: CGFloat = 135, bh: CGFloat = 22
        let bars = (0..<4).map { CGRect(x: 16 + CGFloat($0) * 60, y: ybar, width: 44, height: bh) }
        return SieveMark(
            bars: bars,
            grains: [(CGPoint(x: 68, y: ybar + bh + 26), 11), (CGPoint(x: 188, y: ybar + bh + 56), 8)],
            nugget: (CGPoint(x: 128, y: ybar - 8 - 46), 46)
        )
    }()

    /// Small cut: four 41x32 bars 20 apart, a 50-radius nugget, no grains.
    static let small: SieveMark = {
        let ybar: CGFloat = 142
        let bars = (0..<4).map { CGRect(x: 16 + CGFloat($0) * 61, y: ybar, width: 41, height: 32) }
        return SieveMark(bars: bars, grains: [], nugget: (CGPoint(x: 128, y: ybar - 12 - 50), 50))
    }()
}

let markScale: CGFloat = 3.2
let markOffset = CGPoint(x: canvas / 2 - 128 * markScale, y: canvas / 2 - 128 * markScale + 8)

/// Maps a point on the 256-unit, y-down grid to the 1024 y-up canvas.
func place(_ point: CGPoint) -> CGPoint {
    CGPoint(x: markOffset.x + point.x * markScale, y: canvas - (markOffset.y + point.y * markScale))
}

func placedRect(_ rect: CGRect) -> CGRect {
    let origin = place(CGPoint(x: rect.minX, y: rect.maxY))
    return CGRect(x: origin.x, y: origin.y, width: rect.width * markScale, height: rect.height * markScale)
}

func drawMark(_ mark: SieveMark, in ctx: CGContext) {
    ctx.setFillColor(lightColor)
    for bar in mark.bars {
        let rect = placedRect(bar)
        let radius = rect.height / 2
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    }
    for (center, radius) in mark.grains {
        let c = place(center), r = radius * markScale
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
    ctx.fillPath()
    let c = place(mark.nugget.0), r = mark.nugget.1 * markScale
    ctx.setFillColor(brassColor)
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}

// MARK: - Shape

/// Continuous-corner square: a superellipse |x/a|^n + |y/b|^n = 1 sampled to a path.
func squirclePath(half: CGFloat, exponent n: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let steps = 1440
    let power = 2 / n
    var first = true
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = bodyCenter.x + half * (c < 0 ? -1 : 1) * pow(abs(c), power)
        let y = bodyCenter.y + half * (s < 0 ? -1 : 1) * pow(abs(s), power)
        let point = CGPoint(x: x, y: y)
        if first { path.move(to: point); first = false } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

let bodyPath = squirclePath(half: bodyHalf, exponent: squircleExponent)

// MARK: - Renderer

/// Ink body, rendered once into a transparent 1024 canvas.
let bodyImage: CGImage = {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: Int(canvas), height: Int(canvas),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        FileHandle.standardError.write("could not create body context\n".data(using: .utf8)!)
        exit(1)
    }
    ctx.setShouldAntialias(true)
    ctx.addPath(bodyPath)
    ctx.setFillColor(inkColor)
    ctx.fillPath()
    guard let image = ctx.makeImage() else {
        FileHandle.standardError.write("could not snapshot body\n".data(using: .utf8)!)
        exit(1)
    }
    return image
}()

/// Renders the icon at `pixels` and returns PNG data.
func renderIcon(pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        FileHandle.standardError.write("could not create context for \(pixels) px\n".data(using: .utf8)!)
        exit(1)
    }
    let scale = CGFloat(pixels) / canvas
    let hasShadow = pixels > 32
    ctx.scaleBy(x: scale, y: scale)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // Body + drop shadow (the image's alpha supplies the shadow silhouette).
    // Shadow offset and blur are in device pixels, not the scaled user space,
    // so they are scaled explicitly from the 1024 px design values. At 32 px
    // and below the shadow cannot resolve into a soft ramp and would read as a
    // hard grey band, so those sizes rely on the tile edge alone.
    ctx.saveGState()
    if hasShadow {
        ctx.setShadow(
            offset: CGSize(width: 0, height: -10 * scale),
            blur: 20 * scale,
            color: shadowColor
        )
    }
    ctx.draw(bodyImage, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    ctx.restoreGState()

    // Mark, unshadowed; the small cut keeps the idea readable at 64 px and below.
    drawMark(pixels <= 64 ? .small : .full, in: ctx)

    guard let image = ctx.makeImage() else {
        FileHandle.standardError.write("could not snapshot \(pixels) px icon\n".data(using: .utf8)!)
        exit(1)
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil
    ) else {
        FileHandle.standardError.write("could not create PNG destination\n".data(using: .utf8)!)
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write("could not write PNG for \(pixels) px\n".data(using: .utf8)!)
        exit(1)
    }
    return data as Data
}

// MARK: - Output

/// Filenames and pixel sizes for AppIcon.appiconset/Contents.json.
let iconFiles: [(name: String, pixels: Int)] = [
    ("icon_16.png", 16),
    ("icon_16@2x.png", 32),
    ("icon_32.png", 32),
    ("icon_32@2x.png", 64),
    ("icon_128.png", 128),
    ("icon_128@2x.png", 256),
    ("icon_256.png", 256),
    ("icon_256@2x.png", 512),
    ("icon_512.png", 512),
    ("icon_512@2x.png", 1024),
]

try? FileManager.default.createDirectory(at: iconSetDir, withIntermediateDirectories: true)

for file in iconFiles {
    let png = renderIcon(pixels: file.pixels)
    let url = iconSetDir.appendingPathComponent(file.name)
    try png.write(to: url)
    print("wrote \(url.path) (\(file.pixels)x\(file.pixels))")
}

// Website icon: 1024 px, same artwork as the 1024 master.
let docsPNG = renderIcon(pixels: 1024)
try docsPNG.write(to: docsIconURL)
print("wrote \(docsIconURL.path) (1024x1024)")
