// Draws the Handwritten app icon (notebook paper + ink "h" + text cursor) and writes every size
// into the AppIcon asset set, plus icon.png at the project root.
// Usage: swift scripts/make_icon.swift [projectRoot]
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let iconSet = root.appendingPathComponent("Handwritten/Assets.xcassets/AppIcon.appiconset")

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Small deterministic RNG so the paper grain is identical on every run.
struct Grain {
    var state: UInt64 = 0x2545F4914F6CDD1D
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }
}

func draw(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let g = ctx.cgContext
    let s = CGFloat(size) / 1024
    g.scaleBy(x: s, y: s)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let small = size <= 64

    // macOS icon grid: 824×824 body centered in 1024, corner radius ≈ 185.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft shadow so the sheet sits on the Dock.
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.28))
    g.addPath(bodyPath); g.setFillColor(color(0xF3EDE0)); g.fillPath()
    g.restoreGState()

    // Paper: warm cream, very slightly darker toward the bottom.
    g.saveGState()
    g.addPath(bodyPath); g.clip()
    let paper = CGGradient(colorsSpace: space, colors: [color(0xFCF8EF), color(0xF1E9D8)] as CFArray, locations: [0, 1])!
    g.drawLinearGradient(paper, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])

    // Paper grain (only where it can actually be seen).
    if size >= 128 {
        var r = Grain()
        for _ in 0..<9000 {
            let x = 100 + r.next() * 824, y = 100 + r.next() * 824
            let d = 1.2 + r.next() * 2.2
            let dark = r.next() < 0.6
            g.setFillColor(dark ? color(0x6B5A3A, 0.035 + r.next() * 0.04) : color(0xFFFFFF, 0.25))
            g.fillEllipse(in: CGRect(x: x, y: y, width: d, height: d))
        }
    }

    // Ruled lines (light blue) and the red margin line, like notebook paper.
    let ruleGap: CGFloat = 118
    let baseline: CGFloat = 340
    g.setStrokeColor(color(0x8FB3DC, small ? 0.9 : 0.75))
    g.setLineWidth(small ? 14 : 5)
    var y = baseline - ruleGap
    while y < 924 {
        if y > 110 {
            g.move(to: CGPoint(x: 100, y: y)); g.addLine(to: CGPoint(x: 924, y: y)); g.strokePath()
        }
        y += ruleGap
    }
    g.setStrokeColor(color(0xD9665E, small ? 0.9 : 0.7))
    g.setLineWidth(small ? 12 : 5)
    g.move(to: CGPoint(x: 252, y: 100)); g.addLine(to: CGPoint(x: 252, y: 924)); g.strokePath()

    // Ink "h" sitting on a ruled line.
    let ink = color(0x1F2433)
    let font = NSFont(name: "SnellRoundhand-Black", size: 520) ?? NSFont(name: "SnellRoundhand-Bold", size: 520)
        ?? NSFont.systemFont(ofSize: 420, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(cgColor: ink)!]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "h", attributes: attrs))
    let gb = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    g.textPosition = CGPoint(x: 470 - gb.midX, y: baseline)
    g.setStrokeColor(ink)
    g.setLineJoin(.round)
    g.setLineWidth(size <= 32 ? 40 : (size <= 64 ? 26 : (size <= 128 ? 12 : 5)))
    g.setTextDrawingMode(.fillStroke)
    CTLineDraw(line, g)
    g.setTextDrawingMode(.fill)

    // Text cursor right after the letter, standing on the same line.
    let glyphRight = 470 - gb.midX + gb.maxX
    let cw: CGFloat = size <= 32 ? 50 : (size <= 64 ? 38 : 24)
    let cursor = CGRect(x: min(glyphRight + 34, 790), y: baseline, width: cw, height: 250)
    g.addPath(CGPath(roundedRect: cursor, cornerWidth: cw / 2, cornerHeight: cw / 2, transform: nil))
    g.setFillColor(ink); g.fillPath()

    // A whisper of an edge so the sheet doesn't melt into white backgrounds.
    g.restoreGState()
    g.addPath(bodyPath)
    g.setStrokeColor(color(0x000000, 0.10)); g.setLineWidth(small ? 8 : 3)
    g.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Sizes for the macOS AppIcon set.
let entries: [(pt: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for e in entries {
    let px = e.pt * e.scale
    let name = "icon_\(e.pt)x\(e.pt)\(e.scale == 2 ? "@2x" : "").png"
    try! draw(size: px).representation(using: .png, properties: [:])!.write(to: iconSet.appendingPathComponent(name))
    images.append(["idiom": "mac", "scale": "\(e.scale)x", "size": "\(e.pt)x\(e.pt)", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconSet.appendingPathComponent("Contents.json"))
try! draw(size: 1024).representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("icon.png"))
print("Wrote \(images.count) icon sizes + icon.png")
