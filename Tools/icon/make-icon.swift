// Draws the Transcribation app icon: a sound wave turning into lines of text on a soft indigo-to-blue glass tile.
// Usage: swift Tools/icon/make-icon.swift <output .appiconset folder>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let tileHalf: CGFloat = 412 // macOS icons keep a margin around the tile for the system shadow

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// A superellipse ("squircle") like the system icon shape, sharper than a rounded rectangle.
func tilePath() -> CGPath {
    let path = CGMutablePath()
    let steps = 720
    for step in 0...steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let (cosine, sine) = (cos(angle), sin(angle))
        let point = CGPoint(
            x: canvas / 2 + tileHalf * (cosine < 0 ? -1 : 1) * pow(abs(cosine), 2 / 5),
            y: canvas / 2 + tileHalf * (sine < 0 ? -1 : 1) * pow(abs(sine), 2 / 5)
        )
        step == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func gradient(_ stops: [(UInt32, CGFloat, CGFloat)]) -> CGGradient {
    let colors = stops.map { color($0.0, alpha: $0.2) } as CFArray
    let locations = stops.map(\.1)
    return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: locations)!
}

func roundedBar(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rect.height > rect.width ? rect.width / 2 : rect.height / 2,
           cornerHeight: rect.height > rect.width ? rect.width / 2 : rect.height / 2, transform: nil)
}

func drawGlyph(in context: CGContext) {
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x0B0B45, alpha: 0.35))
    context.setFillColor(color(0xFFFFFF))

    // Sound wave: five bars.
    let heights: [CGFloat] = [130, 270, 400, 250, 150]
    for (index, height) in heights.enumerated() {
        let bar = CGRect(x: 200 + CGFloat(index) * 66, y: 512 - height / 2, width: 42, height: height)
        context.addPath(roundedBar(bar))
        context.fillPath()
    }

    // Text: three lines of decreasing length, fading out like the end of a paragraph.
    let widths: [CGFloat] = [260, 210, 150]
    let alphas: [CGFloat] = [1, 0.86, 0.66]
    for (index, width) in widths.enumerated() {
        context.setFillColor(color(0xFFFFFF, alpha: alphas[index]))
        let line = CGRect(x: 560, y: 512 + 88 - CGFloat(index) * 88 - 21, width: width, height: 42)
        context.addPath(roundedBar(line))
        context.fillPath()
    }
    context.restoreGState()
}

func render(pixels: Int) -> CGImage? {
    guard let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    let tile = tilePath()

    // Soft shadow under the tile.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, alpha: 0.38))
    context.setFillColor(color(0x2A2A80))
    context.addPath(tile)
    context.fillPath()
    context.restoreGState()

    // Tile body: violet at the top left to blue at the bottom right.
    context.saveGState()
    context.addPath(tile)
    context.clip()
    context.drawLinearGradient(
        gradient([(0x9A78FF, 0, 1), (0x5B45F0, 0.5, 1), (0x2A63FF, 1, 1)]),
        start: CGPoint(x: 180, y: 940), end: CGPoint(x: 850, y: 90), options: []
    )
    // Warm glow in the lower left and a light sheen at the top, so the tile reads as glass.
    context.drawRadialGradient(
        gradient([(0xFF5CAA, 0, 0.5), (0xFF5CAA, 1, 0)]),
        startCenter: CGPoint(x: 250, y: 190), startRadius: 0, endCenter: CGPoint(x: 250, y: 190), endRadius: 560, options: []
    )
    context.drawRadialGradient(
        gradient([(0xFFFFFF, 0, 0.32), (0xFFFFFF, 1, 0)]),
        startCenter: CGPoint(x: 400, y: 930), startRadius: 0, endCenter: CGPoint(x: 400, y: 930), endRadius: 660, options: []
    )
    drawGlyph(in: context)

    // Thin inner edge.
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.24))
    context.setLineWidth(5)
    context.addPath(tile)
    context.strokePath()
    context.restoreGState()

    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

// MARK: Output

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output .appiconset folder>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let entries: [(size: String, scale: String, pixels: Int)] = [
    ("16x16", "1x", 16), ("16x16", "2x", 32), ("32x32", "1x", 32), ("32x32", "2x", 64),
    ("128x128", "1x", 128), ("128x128", "2x", 256), ("256x256", "1x", 256), ("256x256", "2x", 512),
    ("512x512", "1x", 512), ("512x512", "2x", 1024),
]

for pixels in Set(entries.map(\.pixels)).sorted() {
    guard let image = render(pixels: pixels) else { throw CocoaError(.fileWriteUnknown) }
    try write(image, to: output.appending(path: "icon_\(pixels).png"))
}

let images = entries.map {
    ["filename": "icon_\($0.pixels).png", "idiom": "mac", "scale": $0.scale, "size": $0.size]
}
let manifest: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appending(path: "Contents.json"))

let catalogManifest: [String: Any] = ["info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalogManifest, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.deletingLastPathComponent().appending(path: "Contents.json"))
print("wrote \(entries.count) icon entries to \(output.path)")
