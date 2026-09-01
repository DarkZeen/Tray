#!/usr/bin/env swift

// Draws Tray's app icon and writes Tray.icns (§56).
//
// Generated rather than checked in as a binary, so the icon is readable,
// reviewable and editable as code — and so a fresh clone with Command Line
// Tools produces exactly the same asset with no design app in the loop.
//
// The mark is a shallow open tray: an outline with a shelf floor sitting low
// inside it. Not a folder — a folder means "files live here", and the whole
// point is that they are passing through.

import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.icns>\n".utf8))
    exit(1)
}

let output = URL(fileURLWithPath: arguments[1])
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Tray-\(UUID().uuidString).iconset")

try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { fatalError("could not allocate a bitmap") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let unit = size / 1024

    // macOS icons sit inside the canvas rather than filling it.
    let plate = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let radius = 185 * unit
    let plateShape = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)

    // Graphite, matching the tray's own surface, lit from above.
    NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.075, green: 0.080, blue: 0.093, alpha: 1),
    ])?.draw(in: plateShape, angle: -90)

    // The highlight that reads as a bevel catching light along the top edge.
    plateShape.addClip()
    let highlight = NSBezierPath(
        roundedRect: plate.insetBy(dx: 3 * unit, dy: 3 * unit),
        xRadius: radius,
        yRadius: radius
    )
    highlight.lineWidth = 6 * unit
    NSColor(calibratedWhite: 1, alpha: 0.13).setStroke()
    highlight.stroke()

    NSGraphicsContext.current?.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // The mark: an open-topped tray with one thing resting in it.
    //
    // Open at the top is what separates a tray from a box. A closed outline
    // reads as a button, or as a minus sign once the interior shrinks; the
    // U-shape reads as a container things go into and come back out of, which
    // is the whole product.
    let markWidth = 548 * unit
    let markHeight = 296 * unit
    let left = (size - markWidth) / 2
    let right = left + markWidth
    let bottom = (size - markHeight) / 2 - 10 * unit
    let top = bottom + markHeight
    let corner = 128 * unit
    let stroke = 54 * unit

    let ink = NSColor(calibratedWhite: 1, alpha: 0.95)

    let tray = NSBezierPath()
    tray.lineWidth = stroke
    tray.lineCapStyle = .round
    tray.lineJoinStyle = .round
    tray.move(to: NSPoint(x: left, y: top))
    tray.line(to: NSPoint(x: left, y: bottom + corner))
    tray.appendArc(
        withCenter: NSPoint(x: left + corner, y: bottom + corner),
        radius: corner,
        startAngle: 180,
        endAngle: 270
    )
    tray.line(to: NSPoint(x: right - corner, y: bottom))
    tray.appendArc(
        withCenter: NSPoint(x: right - corner, y: bottom + corner),
        radius: corner,
        startAngle: 270,
        endAngle: 360
    )
    tray.line(to: NSPoint(x: right, y: top))
    ink.setStroke()
    tray.stroke()

    // The thing in the tray. Standing proud of the walls says "just dropped
    // in" rather than "filed away".
    let tileWidth = 178 * unit
    let tileHeight = 158 * unit
    let tile = NSBezierPath(
        roundedRect: NSRect(
            x: (size - tileWidth) / 2,
            y: bottom + stroke * 0.9,
            width: tileWidth,
            height: tileHeight
        ),
        xRadius: 48 * unit,
        yRadius: 48 * unit
    )
    ink.setFill()
    tile.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// The sizes iconutil expects, at 1× and 2×.
let variants: [(name: String, size: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let rep = drawIcon(size: variant.size)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("could not encode \(variant.name)\n".utf8))
        exit(1)
    }
    try data.write(to: iconset.appendingPathComponent("\(variant.name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()

try? FileManager.default.removeItem(at: iconset)

guard iconutil.terminationStatus == 0 else { exit(iconutil.terminationStatus) }
print("icon → \(output.path)")
