#!/usr/bin/env swift
// Builds Hangover's app icon from the artwork in
// Assets/Brand/Source/hangover-icon-source.png.
//
// The artwork is a rounded tile on a pale background with a soft shadow.
// macOS wants the tile alone on a clear background, at 824 of 1024 points
// with a shadow of its own. This cuts the tile out along its edge, lays it
// on the standard grid, and writes the 1024 master, every slot of the two
// icon sets and OpenIsland.icns. The file names keep the app's internal
// name, which the packaging scripts look for.
//
// Run from the repo root: swift scripts/make-hangover-icon.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let brand = root.appendingPathComponent("Assets/Brand")
let sourceURL = brand.appendingPathComponent("Source/hangover-icon-source.png")

// Where the tile sits in the 1254 by 1254 artwork, measured from its edge
// and pulled in two pixels to leave the background's fringe behind. Top
// left origin. The corner is a plain arc of this radius.
let tile = CGRect(x: 109, y: 107, width: 1035, height: 1037)
let tileRadius: CGFloat = 220

let canvas: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let artwork = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let cut = artwork.cropping(to: tile) else {
    fail("Could not read \(sourceURL.path)")
}

func context(_ side: Int) -> CGContext {
    guard let made = CGContext(
        data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fail("No drawing context") }
    made.interpolationQuality = .high
    return made
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fail("Could not write \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("Could not finish \(url.path)") }
}

// The master: the tile on the standard grid with a soft shadow under it.
let master = context(Int(canvas))
let radius = tileRadius * body.width / tile.width
let outline = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
master.saveGState()
master.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: CGColor(gray: 0, alpha: 0.28))
master.setFillColor(CGColor(srgbRed: 0.98, green: 0.96, blue: 0.92, alpha: 1))
master.addPath(outline)
master.fillPath()
master.restoreGState()
master.addPath(outline)
master.clip()
master.draw(cut, in: body)
guard let masterImage = master.makeImage() else { fail("No master image") }
write(masterImage, to: brand.appendingPathComponent("app-icon-v6.png"))

let slots: [(name: String, side: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for slot in slots {
    let small = context(slot.side)
    small.draw(masterImage, in: CGRect(x: 0, y: 0, width: slot.side, height: slot.side))
    guard let image = small.makeImage() else { fail("No image for \(slot.name)") }
    for set in ["OpenIsland.iconset", "AppIcon.appiconset"] {
        write(image, to: brand.appendingPathComponent(set).appendingPathComponent("\(slot.name).png"))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns", brand.appendingPathComponent("OpenIsland.iconset").path,
    "-o", brand.appendingPathComponent("OpenIsland.icns").path,
]
do {
    try iconutil.run()
    iconutil.waitUntilExit()
} catch {
    fail("iconutil did not run: \(error.localizedDescription)")
}
guard iconutil.terminationStatus == 0 else { fail("iconutil failed with status \(iconutil.terminationStatus)") }
print("Wrote the master, \(slots.count) slots in two sets, and OpenIsland.icns")
