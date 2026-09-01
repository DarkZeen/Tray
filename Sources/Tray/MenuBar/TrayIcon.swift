import AppKit

/// The menu bar glyph (§32).
///
/// Drawn rather than shipped as an asset so it stays crisp at every menu bar
/// height and adapts to light and dark bars through template rendering.
///
/// It reads as a shallow open tray seen head-on — an outline with a shelf
/// floor inside it. Explicitly *not* a folder: a folder means "a place files
/// live", and the whole idea here is that they are only passing through.
enum TrayIcon {
    static func menuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 14)

        let image = NSImage(size: size, flipped: false) { _ in
            let outline = NSBezierPath(
                roundedRect: NSRect(x: 1.6, y: 2.6, width: 14.8, height: 9.2),
                xRadius: 3.1,
                yRadius: 3.1
            )
            outline.lineWidth = 1.35
            NSColor.black.setStroke()
            outline.stroke()

            // The shelf floor. Sitting low in the outline is what separates a
            // tray from a plain rounded rectangle at 16 points.
            let floor = NSBezierPath(
                roundedRect: NSRect(x: 4.4, y: 4.5, width: 9.2, height: 2.1),
                xRadius: 1.05,
                yRadius: 1.05
            )
            NSColor.black.setFill()
            floor.fill()

            return true
        }

        // Template rendering lets macOS invert the glyph for light menu bars,
        // highlight it correctly, and tint it in accent-coloured bars.
        image.isTemplate = true
        return image
    }
}
