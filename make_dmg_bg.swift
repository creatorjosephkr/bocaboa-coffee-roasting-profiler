import Cocoa

let width: CGFloat = 600
let height: CGFloat = 400

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

// Draw background
if let gradient = NSGradient(starting: NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.98, alpha: 1.0),
                             ending: NSColor(calibratedRed: 0.90, green: 0.92, blue: 0.95, alpha: 1.0)) {
    gradient.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)
}

// Draw Title
let title = "보카보아"
let titleFont = NSFont.systemFont(ofSize: 48, weight: .bold)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor(calibratedWhite: 0.2, alpha: 1.0)
]
(title as NSString).draw(at: NSPoint(x: 40, y: 310), withAttributes: titleAttrs)

// Draw Subtitle
let subtitle = "보카보카250BT 커피로스터 로스팅 프로파일러"
let subFont = NSFont.systemFont(ofSize: 18, weight: .medium)
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: subFont,
    .foregroundColor: NSColor(calibratedWhite: 0.4, alpha: 1.0)
]
(subtitle as NSString).draw(at: NSPoint(x: 42, y: 280), withAttributes: subAttrs)

// Draw arrow
let arrowFont = NSFont.systemFont(ofSize: 40, weight: .light)
let arrowAttrs: [NSAttributedString.Key: Any] = [
    .font: arrowFont,
    .foregroundColor: NSColor(calibratedWhite: 0.6, alpha: 1.0)
]
("➜" as NSString).draw(at: NSPoint(x: 280, y: 160), withAttributes: arrowAttrs)

image.unlockFocus()

if let tiffData = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiffData),
   let pngData = bitmap.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "dmg_background.png"))
    print("Background generated: dmg_background.png")
}
