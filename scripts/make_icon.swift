// Renders Sash's app icon into a .iconset directory (passed as arg 1) using CoreGraphics.
// Motif: a window layout (one tall left pane + two right panes) with the top-right pane
// highlighted — a window "snapping" into its zone — on a blue→indigo gradient tile.
import CoreGraphics
import ImageIO
import Foundation

let iconsetDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/AppIcon.iconset"

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func makeIcon(_ px: Int) -> CGImage? {
    let size = CGFloat(px)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                              bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setAllowsAntialiasing(true)

    // Rounded app tile (macOS-style), inset from the edges.
    let inset = size * 0.09
    let tile = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let tilePath = roundedRectPath(tile, radius: size * 0.22)

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    // Vertical gradient: blue (top) → indigo (bottom). CG is y-up, so stop 0 is the bottom.
    let colors = [
        CGColor(red: 0.42, green: 0.36, blue: 1.00, alpha: 1), // bottom (indigo)
        CGColor(red: 0.31, green: 0.55, blue: 1.00, alpha: 1), // top (blue)
    ] as CFArray
    let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.minY),
                           end: CGPoint(x: 0, y: tile.maxY), options: [])
    ctx.restoreGState()

    // Layout of window panes inside the tile.
    let pad = tile.width * 0.17
    let inner = tile.insetBy(dx: pad, dy: pad)
    let gap = inner.width * 0.07
    let leftW = (inner.width - gap) * 0.5          // tall left pane
    let rightW = inner.width - gap - leftW
    let rightH = (inner.height - gap) / 2          // two stacked right panes
    let r = leftW * 0.16

    // Note: CG y-up, so the "top" pane has the larger y.
    let leftPane = CGRect(x: inner.minX, y: inner.minY, width: leftW, height: inner.height)
    let rightTop = CGRect(x: inner.maxX - rightW, y: inner.minY + rightH + gap, width: rightW, height: rightH)
    let rightBot = CGRect(x: inner.maxX - rightW, y: inner.minY, width: rightW, height: rightH)

    // Draw a window pane with a small title-bar strip so it reads as a "window".
    func drawPane(_ rect: CGRect, highlighted: Bool) {
        // Glow behind the highlighted (just-snapped) pane.
        if highlighted {
            ctx.saveGState()
            let glow = rect.insetBy(dx: -size * 0.012, dy: -size * 0.012)
            ctx.setShadow(offset: .zero, blur: size * 0.05,
                          color: CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.addPath(roundedRectPath(glow, radius: r))
            ctx.fillPath()
            ctx.restoreGState()
        }

        let bodyAlpha: CGFloat = highlighted ? 1.0 : 0.55
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: bodyAlpha))
        ctx.addPath(roundedRectPath(rect, radius: r))
        ctx.fillPath()

        // Title-bar strip along the top of the pane.
        let barH = rect.height * 0.2
        let bar = CGRect(x: rect.minX, y: rect.maxY - barH, width: rect.width, height: barH)
        ctx.saveGState()
        ctx.addPath(roundedRectPath(rect, radius: r))
        ctx.clip()
        ctx.setFillColor(CGColor(red: 0.20, green: 0.42, blue: 0.95, alpha: highlighted ? 0.9 : 0.4))
        ctx.fill(bar)
        ctx.restoreGState()
    }

    drawPane(leftPane, highlighted: false)
    drawPane(rightBot, highlighted: false)
    drawPane(rightTop, highlighted: true)   // the pane snapping into place

    return ctx.makeImage()
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// (filename, pixel size) pairs required by iconutil.
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)
for (name, px) in variants {
    if let img = makeIcon(px) {
        write(img, to: iconsetDir + "/" + name)
    }
}
print("Wrote \(variants.count) icon variants to \(iconsetDir)")
