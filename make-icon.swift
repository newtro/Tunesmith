// Renders a simple app icon (gradient rounded square + waveform symbol) into AppIcon.icns.
import AppKit

let sizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

let iconset = URL(fileURLWithPath: "dist/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for (px, name) in sizes {
    let size = NSSize(width: px, height: px)
    let image = NSImage(size: size)
    image.lockFocus()
    let inset = CGFloat(px) * 0.08
    let rect = NSRect(x: inset, y: inset, width: CGFloat(px) - 2 * inset, height: CGFloat(px) - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22)
    NSGradient(colors: [NSColor(calibratedRed: 0.36, green: 0.22, blue: 0.85, alpha: 1),
                        NSColor(calibratedRed: 0.10, green: 0.62, blue: 0.95, alpha: 1)])!
        .draw(in: path, angle: -60)
    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(px) * 0.5, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        let origin = NSPoint(x: (CGFloat(px) - s.width) / 2, y: (CGFloat(px) - s.height) / 2)
        NSColor.white.set()
        symbol.isTemplate = true
        let tinted = NSImage(size: s)
        tinted.lockFocus()
        symbol.draw(at: .zero, from: NSRect(origin: .zero, size: s), operation: .sourceOver, fraction: 1)
        NSColor.white.set()
        NSRect(origin: .zero, size: s).fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.draw(at: origin, from: NSRect(origin: .zero, size: s), operation: .sourceOver, fraction: 1)
    }
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try! png.write(to: iconset.appendingPathComponent("\(name).png"))
}
print("iconset written")
