#!/usr/bin/env swift
//
// make-icon.swift — regenerates the Sift app icon from vectors.
//
// Usage: swift scripts/make-icon.swift
//
// Spec (macOS Big Sur+ icon grid):
//   canvas          1024x1024, transparent outside the shape
//   body            824x824 centered, continuous-corner squircle (superellipse n=5,
//                   equivalent to a ~185 px rounded rect), brass #C9A227 with a
//                   subtle vertical gradient #D4AE36 -> #BE981F
//   shadow          black 30%, y+10 px, blur 20 px, inside the canvas; both
//                   scale with the output size (1024 px reference) and are
//                   omitted at 32 px and below
//   mark            "S" in Archivo Narrow Bold (wght 700), #0D0F11,
//                   cap height 52% of the body height, ink-centered
//
// Every size is rasterized independently from the vectors, so nothing is
// downscaled from one master bitmap.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Paths

let scriptURL = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let fontURL = repoRoot.appendingPathComponent("Sift/Resources/Fonts/ArchivoNarrow.ttf")
let iconSetDir = repoRoot.appendingPathComponent("Sift/Assets.xcassets/AppIcon.appiconset")
let docsIconURL = repoRoot.appendingPathComponent("docs/assets/icon.png")

// MARK: - Geometry (1024 px design space)

let canvas: CGFloat = 1024
let bodySize: CGFloat = 824
let bodyHalf = bodySize / 2
let bodyCenter = CGPoint(x: canvas / 2, y: canvas / 2)
let squircleExponent: CGFloat = 5 // continuous-corner approximation of r ≈ 185 px
let baseCapRatio: CGFloat = 0.52

// MARK: - Colors

func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

let gradientTop = srgb(0xD4AE36)
let gradientBottom = srgb(0xBE981F)
let inkColor = srgb(0x0D0F11)
let shadowColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.3)

// MARK: - Typography

var fontRegistrationError: Unmanaged<CFError>?
if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &fontRegistrationError) {
    // Already registered in this process is fine; anything else is fatal.
    if let error = fontRegistrationError?.takeRetainedValue(),
       CFErrorGetCode(error) != 105 { // kCTFontManagerErrorAlreadyRegistered
        FileHandle.standardError.write("font registration failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

let fontDescriptors = (CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor]) ?? []
guard let baseDescriptor = fontDescriptors.first else {
    FileHandle.standardError.write("no font descriptors in \(fontURL.path)\n".data(using: .utf8)!)
    exit(1)
}

let weightTag = NSNumber(value: 0x77676874) // 'wght'
let boldVariation: CFDictionary = [weightTag: 700] as CFDictionary
let boldDescriptor = CTFontDescriptorCreateCopyWithAttributes(
    baseDescriptor,
    [kCTFontVariationAttribute: boldVariation] as CFDictionary
)
let measuredBold = CTFontCreateWithFontDescriptor(boldDescriptor, 1000, nil)
let capRatio = CTFontGetCapHeight(measuredBold) / 1000 // cap height per em

guard var sGlyph: CGGlyph = {
    var glyph: CGGlyph = 0
    var character: UniChar = 0x53 // "S"
    return CTFontGetGlyphsForCharacters(measuredBold, &character, &glyph, 1) ? glyph : nil
}()
else {
    FileHandle.standardError.write("font has no glyph for S\n".data(using: .utf8)!)
    exit(1)
}

/// Glyph outline for "S" at the requested cap height, ink-centered on the body.
func markPath(capHeight: CGFloat, opticalNudge: CGFloat = 0) -> (path: CGPath, size: CGFloat) {
    let fontSize = capHeight / capRatio
    let font = CTFontCreateWithFontDescriptor(boldDescriptor, fontSize, nil)
    guard let glyphPath = CTFontCreatePathForGlyph(font, sGlyph, nil) else {
        FileHandle.standardError.write("could not build glyph path\n".data(using: .utf8)!)
        exit(1)
    }
    let ink = glyphPath.boundingBoxOfPath
    var transform = CGAffineTransform(
        translationX: bodyCenter.x - ink.midX,
        y: bodyCenter.y - ink.midY + opticalNudge
    )
    guard let placed = glyphPath.copy(using: &transform) else {
        FileHandle.standardError.write("could not place glyph path\n".data(using: .utf8)!)
        exit(1)
    }
    return (placed, fontSize)
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

/// Brass body with its gradient, rendered once into a transparent 1024 canvas.
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
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [gradientTop, gradientBottom] as CFArray, locations: [0, 1])!
    // y-up context: the body's top edge is the start, its bottom edge the end,
    // so the ramp hits #D4AE36 and #BE981F exactly at the shape's edges.
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: bodyCenter.y + bodyHalf),
        end: CGPoint(x: 0, y: bodyCenter.y - bodyHalf),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    guard let image = ctx.makeImage() else {
        FileHandle.standardError.write("could not snapshot body\n".data(using: .utf8)!)
        exit(1)
    }
    return image
}()

/// Renders the icon at `pixels` and returns PNG data.
func renderIcon(pixels: Int, capRatio: CGFloat) -> Data {
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

    // Mark, unshadowed.
    let capHeight = bodySize * capRatio
    let mark = markPath(capHeight: capHeight)
    ctx.addPath(mark.path)
    ctx.setFillColor(inkColor)
    ctx.fillPath()

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

/// Small sizes lose weight when the mark keeps its 52% cap height, so the S is
/// grown slightly at 16 and 32 px only.
func capRatio(forPixels pixels: Int) -> CGFloat {
    switch pixels {
    case ..<24: return 0.60
    case ..<48: return 0.56
    default: return baseCapRatio
    }
}

try? FileManager.default.createDirectory(at: iconSetDir, withIntermediateDirectories: true)

for file in iconFiles {
    let png = renderIcon(pixels: file.pixels, capRatio: capRatio(forPixels: file.pixels))
    let url = iconSetDir.appendingPathComponent(file.name)
    try png.write(to: url)
    print("wrote \(url.path) (\(file.pixels)x\(file.pixels))")
}

// Website icon: 1024 px, same artwork as the 1024 master.
let docsPNG = renderIcon(pixels: 1024, capRatio: baseCapRatio)
try docsPNG.write(to: docsIconURL)
print("wrote \(docsIconURL.path) (1024x1024)")
