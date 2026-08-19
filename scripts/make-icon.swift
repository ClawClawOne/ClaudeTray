import AppKit
import CoreGraphics

let out = CommandLine.arguments[1]

func draw(size S: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    ctx.setAllowsAntialiasing(true)

    // Gabarit macOS : le dessin occupe ~80 % du canevas, le reste est la marge de l'icône.
    let inset = S * 0.10
    let rect = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
    let radius = rect.width * 0.2237

    let body = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let space = CGColorSpaceCreateDeviceRGB()
    let bg = CGGradient(colorsSpace: space,
                        colors: [CGColor(red: 0.20, green: 0.19, blue: 0.18, alpha: 1),
                                 CGColor(red: 0.09, green: 0.09, blue: 0.08, alpha: 1)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: rect.minX, y: rect.maxY),
                           end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    ctx.restoreGState()

    // Jauge : anneau de 270°, rempli aux trois quarts, comme un quota entamé.
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let ringRadius = rect.width * 0.29
    let width = rect.width * 0.115
    let start = CGFloat.pi * 1.25
    let sweep = CGFloat.pi * 1.5

    ctx.setLineCap(.round)
    ctx.setLineWidth(width)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    ctx.addArc(center: center, radius: ringRadius, startAngle: start,
               endAngle: start - sweep, clockwise: true)
    ctx.strokePath()

    ctx.setStrokeColor(CGColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1))
    ctx.addArc(center: center, radius: ringRadius, startAngle: start,
               endAngle: start - sweep * 0.72, clockwise: true)
    ctx.strokePath()

    // Point de tête : rend la fin de l'arc lisible même à 16 px.
    let head = start - sweep * 0.72
    let dot = CGPoint(x: center.x + cos(head) * ringRadius, y: center.y + sin(head) * ringRadius)
    ctx.setFillColor(CGColor(red: 1, green: 0.88, blue: 0.82, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: dot.x - width * 0.26, y: dot.y - width * 0.26,
                               width: width * 0.52, height: width * 0.52))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]
for (px, name) in sizes {
    try! draw(size: CGFloat(px)).write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("ok")
