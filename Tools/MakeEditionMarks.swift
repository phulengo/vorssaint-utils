// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

// Draws a renamed copy's own marks from one silhouette (only its alpha
// counts; both are template images): the menu bar glyph at 1x and 2x on the
// canvas StatusItemController expects, and the BrandMark the app shows in
// its windows. Used by Tools/make-edition.sh.
//
//   swift Tools/MakeEditionMarks.swift MARK.png OUTPUT_FOLDER

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let mark = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write(Data("usage: swift Tools/MakeEditionMarks.swift MARK.png OUTPUT_FOLDER\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
// Keep in sync with the menu bar canvas in Tools/MakeIcon.swift.
let canvas = NSSize(width: 26, height: 20)
let glyphHeight: CGFloat = 15

func render(width: Int, height: Int, draw: (CGRect) -> Void) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let aspect = mark.size.width / mark.size.height
for scale in [1, 2] {
    let s = CGFloat(scale)
    let height = glyphHeight * s, width = min(canvas.width * s, height * aspect)
    let data = render(width: Int(canvas.width * s), height: Int(canvas.height * s)) { bounds in
        let fitted = CGSize(width: width, height: width / aspect)
        mark.draw(in: CGRect(x: ((bounds.width - fitted.width) / 2).rounded(), y: ((bounds.height - fitted.height) / 2).rounded(),
                             width: fitted.width, height: fitted.height))
    }
    try data?.write(to: output.appendingPathComponent(scale == 1 ? "MenuBarIcon.png" : "MenuBarIcon@2x.png"))
}
let brandWidth = 640, brandHeight = Int((640 / aspect).rounded())
let brand = render(width: brandWidth, height: brandHeight) { mark.draw(in: $0) }
try brand?.write(to: output.appendingPathComponent("BrandMark.png"))
print("marks drawn")
