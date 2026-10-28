// Renders the app icon PNG: swift Icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
ctx.addPath(CGPath(roundedRect: body, cornerWidth: 180, cornerHeight: 180, transform: nil))
ctx.setFillColor(CGColor(red: 0.016, green: 0.03, blue: 0.04, alpha: 1))
ctx.fillPath()

let cyan = CGColor(red: 0.18, green: 0.95, blue: 0.88, alpha: 1)
let amber = CGColor(red: 1, green: 0.64, blue: 0.11, alpha: 1)
let mid = size / 2
let cell: CGFloat = 34, step: CGFloat = 44
let heights = [3, 5, 4, 7, 6, 8, 5, 6, 4, 3, 2, 4, 3, 5, 4, 2, 3]
ctx.setShadow(offset: .zero, blur: 30, color: cyan)
for (i, h) in heights.enumerated() {
    let x = body.minX + 60 + CGFloat(i) * step
    if x + cell > body.maxX - 50 { break }
    let up = i >= 10
    ctx.setFillColor(up ? amber : cyan)
    for r in 0..<h {
        let y = up ? mid + 8 + CGFloat(r) * step : mid - 8 - cell - CGFloat(r) * step
        ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
    }
}
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.setFillColor(CGColor(gray: 0, alpha: 0.3))
for y in stride(from: body.minY, to: body.maxY, by: 12) {
    ctx.fill(CGRect(x: body.minX, y: y, width: body.width, height: 5))
}
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
