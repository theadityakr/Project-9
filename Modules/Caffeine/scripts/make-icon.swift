#!/usr/bin/env swift
// make-icon.swift — Renders an SF Symbol into a proper .icns file.
//
// Usage:  swift scripts/make-icon.swift [--symbol <name>] [--output <path>]
// Output: Caffeine.icns (default)
//
// Requires macOS 13+ / Xcode CLT

import AppKit
import Foundation

// ─── Args ─────────────────────────────────────────────────────────────────────
var symbolName  = "cup.and.saucer.fill"
var outputPath  = "Caffeine.icns"

var args = CommandLine.arguments.dropFirst()
while !args.isEmpty {
    switch args.first {
    case "--symbol":
        args = args.dropFirst()
        symbolName = args.first ?? symbolName
    case "--output":
        args = args.dropFirst()
        outputPath = args.first ?? outputPath
    default: break
    }
    if !args.isEmpty { args = args.dropFirst() }
}

// ─── Required icon sizes (px) ─────────────────────────────────────────────────
// Each entry is (folder-suffix, pixel-size)
let iconSizes: [(String, Int)] = [
    ("16x16",       16),
    ("16x16@2x",    32),
    ("32x32",       32),
    ("32x32@2x",    64),
    ("128x128",    128),
    ("128x128@2x", 256),
    ("256x256",    256),
    ("256x256@2x", 512),
    ("512x512",    512),
    ("512x512@2x",1024),
]

// ─── Render helper ────────────────────────────────────────────────────────────
func renderSymbol(_ symbol: String, size: Int) -> NSImage? {
    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.6,
                                              weight: .medium,
                                              scale: .large)
    guard let sf = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                     .withSymbolConfiguration(config) else { return nil }

    // Composite onto a rounded-rect warm-gradient background
    let canvas = NSImage(size: NSSize(width: size, height: size))
    canvas.lockFocus()

    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))

    // Background gradient: orange → amber
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 1.0, green: 0.60, blue: 0.10, alpha: 1),   // orange
            CGColor(red: 1.0, green: 0.78, blue: 0.10, alpha: 1),   // amber
        ] as CFArray,
        locations: [0, 1]
    )!

    let corner = CGFloat(size) * 0.225
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: CGFloat(size)),
                           end:   CGPoint(x: CGFloat(size), y: 0),
                           options: [])

    // Drop-shadow for the symbol
    ctx.setShadow(offset: CGSize(width: 0, height: -CGFloat(size) * 0.04),
                  blur: CGFloat(size) * 0.08,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.25))

    // Center the symbol
    let symSize = sf.size
    let origin  = NSPoint(
        x: (CGFloat(size) - symSize.width)  / 2,
        y: (CGFloat(size) - symSize.height) / 2
    )
    sf.draw(at: origin,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0)

    canvas.unlockFocus()
    return canvas
}

// ─── Build the iconset ────────────────────────────────────────────────────────
let fm = FileManager.default
let iconsetPath = (outputPath as NSString).deletingPathExtension + ".iconset"

try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (suffix, px) in iconSizes {
    guard let image = renderSymbol(symbolName, size: px) else {
        fputs("⚠️  Could not render \(symbolName) at \(px)px\n", stderr)
        continue
    }

    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("⚠️  PNG conversion failed at \(px)px\n", stderr)
        continue
    }

    let file = "\(iconsetPath)/icon_\(suffix).png"
    try png.write(to: URL(fileURLWithPath: file))
}

// ─── Convert to ICNS ─────────────────────────────────────────────────────────
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "-o", outputPath, iconsetPath]
try task.run()
task.waitUntilExit()

try? fm.removeItem(atPath: iconsetPath)   // clean up temp folder

if task.terminationStatus == 0 {
    print("✅  Icon written to \(outputPath)")
} else {
    fputs("❌  iconutil failed (exit \(task.terminationStatus))\n", stderr)
    exit(task.terminationStatus)
}
