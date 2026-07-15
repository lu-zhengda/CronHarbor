#!/usr/bin/env swift

import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDirectory = root.appendingPathComponent("Resources/AppIcon.iconset")
let outputFile = root.appendingPathComponent("Resources/AppIcon.icns")
let previewFile = root.appendingPathComponent("docs/design/cronharbor-app-icon.png")

try? FileManager.default.removeItem(at: outputDirectory)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func render(size: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "CronHarborIcon", code: 1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    defer { NSGraphicsContext.restoreGraphicsState() }

    let context = graphicsContext.cgContext

    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)

    let tile = CGRect(x: 44, y: 44, width: 936, height: 936)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 220, cornerHeight: 220, transform: nil)
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let colors = [
        NSColor(calibratedRed: 0.10, green: 0.47, blue: 0.92, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.05, green: 0.20, blue: 0.55, alpha: 1).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 200, y: 920), end: CGPoint(x: 850, y: 80), options: [])
    context.restoreGState()

    context.setStrokeColor(NSColor.white.cgColor)
    context.setFillColor(NSColor.white.cgColor)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(68)

    context.strokeEllipse(in: CGRect(x: 438, y: 690, width: 148, height: 148))
    context.move(to: CGPoint(x: 512, y: 688))
    context.addLine(to: CGPoint(x: 512, y: 260))
    context.strokePath()

    context.move(to: CGPoint(x: 340, y: 575))
    context.addLine(to: CGPoint(x: 684, y: 575))
    context.strokePath()

    context.setLineWidth(72)
    context.move(to: CGPoint(x: 255, y: 390))
    context.addCurve(
        to: CGPoint(x: 512, y: 190),
        control1: CGPoint(x: 270, y: 250),
        control2: CGPoint(x: 385, y: 190)
    )
    context.addCurve(
        to: CGPoint(x: 769, y: 390),
        control1: CGPoint(x: 639, y: 190),
        control2: CGPoint(x: 754, y: 250)
    )
    context.strokePath()

    context.move(to: CGPoint(x: 230, y: 400))
    context.addLine(to: CGPoint(x: 290, y: 475))
    context.move(to: CGPoint(x: 794, y: 400))
    context.addLine(to: CGPoint(x: 734, y: 475))
    context.strokePath()

    context.setFillColor(NSColor(calibratedRed: 1, green: 0.67, blue: 0.16, alpha: 1).cgColor)
    context.fillEllipse(in: CGRect(x: 666, y: 642, width: 218, height: 218))
    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(28)
    context.strokeEllipse(in: CGRect(x: 686, y: 662, width: 178, height: 178))
    context.setLineWidth(24)
    context.move(to: CGPoint(x: 775, y: 751))
    context.addLine(to: CGPoint(x: 775, y: 800))
    context.move(to: CGPoint(x: 775, y: 751))
    context.addLine(to: CGPoint(x: 818, y: 726))
    context.strokePath()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CronHarborIcon", code: 2)
    }
    return png
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for variant in variants {
    try render(size: variant.pixels).write(to: outputDirectory.appendingPathComponent(variant.name))
}

func bigEndianData(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return Data(bytes: &number, count: MemoryLayout<UInt32>.size)
}

let iconChunks: [(type: String, pixels: Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024)
]

var chunkData = Data()
for chunk in iconChunks {
    let png = try render(size: chunk.pixels)
    chunkData.append(Data(chunk.type.utf8))
    chunkData.append(bigEndianData(png.count + 8))
    chunkData.append(png)
}

var icns = Data("icns".utf8)
icns.append(bigEndianData(chunkData.count + 8))
icns.append(chunkData)
try icns.write(to: outputFile, options: .atomic)
try render(size: 1024).write(to: previewFile, options: .atomic)

try? FileManager.default.removeItem(at: outputDirectory)
print(outputFile.path)
