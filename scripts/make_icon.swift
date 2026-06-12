// Generates App/Resources/stimd.icns: a macOS-style squircle with an "M↓" glyph.
// Run: swift scripts/make_icon.swift
import AppKit

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    let s = CGFloat(pixels)
    let inset = s * 0.082
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = (s - inset * 2) * 0.225

    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Subtle drop shadow
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.02
    shadow.set()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.30, alpha: 1.0),
        NSColor(calibratedRed: 0.28, green: 0.34, blue: 0.62, alpha: 1.0),
    ])!
    gradient.draw(in: squircle, angle: 90)

    NSShadow().set()

    // Inner highlight stroke
    NSColor.white.withAlphaComponent(0.12).setStroke()
    let strokePath = NSBezierPath(
        roundedRect: rect.insetBy(dx: s * 0.004, dy: s * 0.004),
        xRadius: radius, yRadius: radius
    )
    strokePath.lineWidth = s * 0.008
    strokePath.stroke()

    // "stimd" wordmark, scaled to fit the squircle
    let text = "stimd" as NSString
    var fontSize = s * 0.30
    func attrs(_ size: CGFloat) -> [NSAttributedString.Key: Any] {
        var font = NSFont.systemFont(ofSize: size, weight: .bold)
        if let desc = font.fontDescriptor.withDesign(.rounded).flatMap({ NSFont(descriptor: $0, size: size) }) {
            font = desc
        }
        return [.font: font, .foregroundColor: NSColor.white, .kern: size * -0.02]
    }
    while text.size(withAttributes: attrs(fontSize)).width > s * 0.70 {
        fontSize *= 0.95
    }
    let a = attrs(fontSize)
    let size = text.size(withAttributes: a)
    text.draw(
        at: NSPoint(x: (s - size.width) / 2, y: (s - size.height) / 2 + s * 0.005),
        withAttributes: a
    )

    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let iconset = "stimd.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for entry in entries {
    savePNG(drawIcon(pixels: entry.pixels), to: "\(iconset)/\(entry.name).png")
}

print("iconset written to \(iconset)")
