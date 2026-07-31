import AppKit

let outputURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "pickroom-icon.png")
let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Unable to create drawing context")
}

context.setFillColor(NSColor(
    calibratedRed: 0.055,
    green: 0.065,
    blue: 0.078,
    alpha: 1
).cgColor)
context.fill(CGRect(origin: .zero, size: size))

func roundedRect(_ rect: CGRect, radius: CGFloat, color: NSColor, alpha: CGFloat = 1) {
    color.withAlphaComponent(alpha).setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

roundedRect(
    CGRect(x: 196, y: 236, width: 560, height: 470),
    radius: 52,
    color: .white,
    alpha: 0.16
)
roundedRect(
    CGRect(x: 246, y: 286, width: 580, height: 486),
    radius: 52,
    color: .white,
    alpha: 0.94
)
roundedRect(
    CGRect(x: 300, y: 340, width: 472, height: 378),
    radius: 28,
    color: NSColor(calibratedRed: 0.075, green: 0.085, blue: 0.10, alpha: 1)
)

let accent = NSColor(calibratedRed: 0.18, green: 0.72, blue: 0.82, alpha: 1)
accent.setStroke()

let lineWidth: CGFloat = 32
let cornerLength: CGFloat = 92
let focusRect = CGRect(x: 382, y: 420, width: 308, height: 224)
let focusPath = NSBezierPath()
focusPath.lineWidth = lineWidth
focusPath.lineCapStyle = .round

focusPath.move(to: CGPoint(x: focusRect.minX + cornerLength, y: focusRect.maxY))
focusPath.line(to: CGPoint(x: focusRect.minX, y: focusRect.maxY))
focusPath.line(to: CGPoint(x: focusRect.minX, y: focusRect.maxY - cornerLength))

focusPath.move(to: CGPoint(x: focusRect.maxX - cornerLength, y: focusRect.maxY))
focusPath.line(to: CGPoint(x: focusRect.maxX, y: focusRect.maxY))
focusPath.line(to: CGPoint(x: focusRect.maxX, y: focusRect.maxY - cornerLength))

focusPath.move(to: CGPoint(x: focusRect.minX, y: focusRect.minY + cornerLength))
focusPath.line(to: CGPoint(x: focusRect.minX, y: focusRect.minY))
focusPath.line(to: CGPoint(x: focusRect.minX + cornerLength, y: focusRect.minY))

focusPath.move(to: CGPoint(x: focusRect.maxX, y: focusRect.minY + cornerLength))
focusPath.line(to: CGPoint(x: focusRect.maxX, y: focusRect.minY))
focusPath.line(to: CGPoint(x: focusRect.maxX - cornerLength, y: focusRect.minY))
focusPath.stroke()

roundedRect(
    CGRect(x: 505, y: 500, width: 64, height: 64),
    radius: 32,
    color: accent
)

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fatalError("Unable to encode icon")
}

try png.write(to: outputURL)
