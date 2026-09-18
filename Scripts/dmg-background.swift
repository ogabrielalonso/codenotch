// Draws the window the disk image opens on, and writes where its two icons
// go, so the arrow and the icons it points between cannot drift apart:
//
//   swift Scripts/dmg-background.swift <out-dir>
//
// writes background.png (1x), background@2x.png and layout.json, which
// Scripts/dmg-settings.py reads. `make dmg-ci` runs both.
//
// The background is light on purpose. Over a picture, Finder draws the icons'
// names in black whatever the Mac's Appearance (checked on macOS 26 in Dark
// mode), so on the black the notch is made of they would not show at all. The
// black is kept for the notch itself, drawn the way the app draws it.
import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: dmg-background.swift <out-dir>\n".utf8))
    exit(64)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

// The window's content area, in points. Finder draws the title bar above it,
// and the path and status bars over its bottom when someone has them on, so
// nothing that matters sits in the bottom 60pt.
let width: CGFloat = 640
let height: CGFloat = 380
let iconSize: CGFloat = 112
let iconY: CGFloat = 212
let appX: CGFloat = 176
let applicationsX: CGFloat = width - appX
let caption = "Drag Codenotch to Applications"

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha)
}

// The app's notch at 26/44 of its size: a 26pt ring where the app draws a
// 44pt one, and every other measure of NotchLayout scaled with it (the app's
// design-frame pixels are 44/117pt each).
let k: CGFloat = 26 / 44
func px(_ pixels: CGFloat) -> CGFloat { pixels * 44 / 117 * k }
let ringDiameter = px(117)
let ringMargin = px((186 - 117) / 2)
let flare = px(103)
let corner = px(78.8)
let trackStroke = px(15.5)
let progressStroke = px(8)
let ringGap: CGFloat = 16
// The readings from docs/design/frame-125-detail.png, in its colours.
let rings: [(fraction: CGFloat, colour: NSColor)] = [
    (0.73, hex(0xFF3F00)),  // Palette.critical
    (0.21, hex(0x00FF88)),  // Palette.ample, dark
    (0.52, hex(0xF2FF00)),  // Palette.watch, dark
]

/// SideNotchShape for the top edge, written out directly: a body hanging from
/// the top with rounded bottom corners, and inverse corners where it flares
/// back out to the edge.
func notchPath(bodyWidth: CGFloat, depth: CGFloat, centreX: CGFloat) -> NSBezierPath {
    let r = min(corner, depth / 2)
    let left = centreX - bodyWidth / 2
    let right = centreX + bodyWidth / 2
    let path = NSBezierPath()
    path.move(to: NSPoint(x: left - flare, y: 0))
    path.appendArc(withCenter: NSPoint(x: left - flare, y: flare), radius: flare,
                   startAngle: 270, endAngle: 360, clockwise: false)
    path.line(to: NSPoint(x: left, y: depth - r))
    path.appendArc(withCenter: NSPoint(x: left + r, y: depth - r), radius: r,
                   startAngle: 180, endAngle: 90, clockwise: true)
    path.line(to: NSPoint(x: right - r, y: depth))
    path.appendArc(withCenter: NSPoint(x: right - r, y: depth - r), radius: r,
                   startAngle: 90, endAngle: 0, clockwise: true)
    path.line(to: NSPoint(x: right, y: flare))
    path.appendArc(withCenter: NSPoint(x: right + flare, y: flare), radius: flare,
                   startAngle: 180, endAngle: 270, clockwise: false)
    path.close()
    return path
}

func draw() {
    // Top-left origin, as Finder places icons.
    let background = NSGradient(starting: hex(0xF7F7F8), ending: hex(0xECECEF))!
    background.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

    // The notch, flush with the top of the window as the app's is with the
    // top of the screen.
    let depth = 2 * ringMargin + ringDiameter
    let ringsLength = CGFloat(rings.count) * ringDiameter + CGFloat(rings.count - 1) * ringGap
    let bodyWidth = ringsLength + 2 * (ringMargin + corner / 2)
    NSColor.black.setFill()
    notchPath(bodyWidth: bodyWidth, depth: depth, centreX: width / 2).fill()

    for (index, ring) in rings.enumerated() {
        let centre = NSPoint(
            x: width / 2 - ringsLength / 2 + ringDiameter / 2 + CGFloat(index) * (ringDiameter + ringGap),
            y: ringMargin + ringDiameter / 2
        )
        let radius = ringDiameter / 2 - trackStroke / 2
        let track = NSBezierPath()
        track.appendArc(withCenter: centre, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = trackStroke
        NSColor.white.withAlphaComponent(0.188).setStroke()  // Palette.ringTrack, dark
        track.stroke()

        // From twelve o'clock, clockwise on screen. The context is flipped,
        // so on screen clockwise is increasing angle here.
        let arc = NSBezierPath()
        arc.appendArc(withCenter: centre, radius: radius,
                      startAngle: 270, endAngle: 270 + 360 * ring.fraction, clockwise: false)
        arc.lineWidth = progressStroke
        arc.lineCapStyle = .round
        ring.colour.setStroke()
        arc.stroke()
    }

    // The arrow, between where the two icons' artwork ends.
    let gap: CGFloat = 30
    let start = appX + iconSize / 2 + gap
    let end = applicationsX - iconSize / 2 - gap
    let head: CGFloat = 10
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: start, y: iconY))
    arrow.line(to: NSPoint(x: end, y: iconY))
    arrow.move(to: NSPoint(x: end - head, y: iconY - head))
    arrow.line(to: NSPoint(x: end, y: iconY))
    arrow.line(to: NSPoint(x: end - head, y: iconY + head))
    arrow.lineWidth = 3
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    hex(0x6B6B6B).setStroke()  // Palette.textSecondary, light: 4.9:1 here
    arrow.stroke()

    // The instruction, set as the window's heading and kept with the icons
    // it is about; above them, the path and status bars can never cover it.
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let text = NSAttributedString(string: caption, attributes: [
        .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        .foregroundColor: hex(0x000000, 0.85),
        .paragraphStyle: paragraph,
    ])
    let textHeight = text.size().height
    text.draw(in: NSRect(x: 0, y: 138 - textHeight / 2, width: width, height: textHeight))
}

func render(scale: CGFloat, to url: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    // Points, not pixels: this is what makes the 2x image 144 dpi, and what
    // tiffutil checks when it pairs the two.
    rep.size = NSSize(width: width, height: height)
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: height)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
try render(scale: 1, to: outDir.appendingPathComponent("background.png"))
try render(scale: 2, to: outDir.appendingPathComponent("background@2x.png"))

let layout: [String: Any] = [
    "width": width, "height": height, "icon_size": iconSize,
    "app": [appX, iconY], "applications": [applicationsX, iconY],
]
try JSONSerialization.data(withJSONObject: layout, options: [.prettyPrinted, .sortedKeys])
    .write(to: outDir.appendingPathComponent("layout.json"))
