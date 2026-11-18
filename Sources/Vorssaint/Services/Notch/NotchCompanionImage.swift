// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

enum NotchCompanionImageSupport {
    /// The largest file accepted when choosing a picture.
    static let maximumBytes = 32 * 1_024 * 1_024
    /// The companion is drawn a few dozen points across at most, in the
    /// island or a Settings preview, so frames are kept at this size.
    static let keptPixels = 256
    static let maximumFrames = 600
    static let folderName = "NotchCompanion"

    /// Whether `name` is one of the companion folder's own files.
    static func isCompanionFile(_ name: String) -> Bool {
        (name.hasSuffix(".png") || name.hasSuffix(".gif")) && !name.contains("/") && !name.hasPrefix(".")
            && name.count <= 64
    }

    /// The picture's frames and how long each shows, shrunk to `keptPixels`.
    /// A still picture is one frame. Nil for anything that is not a picture.
    static func frames(_ data: Data, pixels: Int = keptPixels) -> [(image: CGImage, delay: Double)]? {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = min(CGImageSourceGetCount(source), maximumFrames)
        guard count > 0 else { return nil }
        let shrink = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary
        var frames: [(image: CGImage, delay: Double)] = []
        for index in 0..<count {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, shrink) else { return nil }
            let gif = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary]
                as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            // Browsers show a frame of no delay for a tenth of a second, and so does this.
            frames.append((image, delay > 0.011 ? delay : 0.1))
        }
        return frames
    }

    /// Whether a picture already has see-through parts, as a cut-out PNG or
    /// a GIF drawn for a dark background does.
    static func hasTransparency(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return false
        default: break
        }
        // An alpha channel can still be opaque everywhere; look at a small copy.
        let side = 32
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn && stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] < 250 }
    }

    /// The subject of a still picture lifted off its background, cropped to
    /// it, the way Photos lifts a subject. Nil when Vision finds none.
    static func liftedSubject(_ image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil, let result = request.results?.first,
              !result.allInstances.isEmpty,
              let mask = try? result.generateMaskedImage(ofInstances: result.allInstances, from: handler,
                                                         croppedToInstancesExtent: true) else { return nil }
        let picture = CIImage(cvPixelBuffer: mask)
        return CIContext().createCGImage(picture, from: picture.extent)
    }

    /// The picture as it is kept: a PNG for a still one, a GIF with every
    /// frame's own delay for a moving one. A still photo with a solid
    /// background has its subject lifted off it, so only the figure shows on
    /// the black island.
    static func kept(_ data: Data) -> (data: Data, animated: Bool)? {
        guard var frames = frames(data) else { return nil }
        if frames.count == 1, let still = frames.first?.image, !hasTransparency(still),
           let subject = liftedSubject(still) {
            frames = [(subject, frames[0].delay)]
        }
        let animated = frames.count > 1
        let output = NSMutableData()
        let type = (animated ? UTType.gif : UTType.png).identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(output, type, frames.count, nil) else { return nil }
        if animated {
            CGImageDestinationSetProperties(destination,
                                            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        }
        for frame in frames {
            let properties = animated
                ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frame.delay]] as CFDictionary : nil
            CGImageDestinationAddImage(destination, frame.image, properties)
        }
        return CGImageDestinationFinalize(destination) ? (output as Data, animated) : nil
    }
}

/// The custom companion's picture: one picture or GIF the person chose,
/// shrunk and kept in the app's private folder. The companion reads only
/// that copy, decoded once and shared by every place it is drawn.
final class NotchCompanionImage {
    static let shared = NotchCompanionImage()

    private var cache: (name: String, frames: [(image: CGImage, delay: Double)])?

    private static var folder: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent(NotchCompanionImageSupport.folderName, isDirectory: true)
    }

    /// The frames of the picture kept as `name`, nil when there is none.
    func frames(named name: String) -> [(image: CGImage, delay: Double)]? {
        guard NotchCompanionImageSupport.isCompanionFile(name) else { return nil }
        if let cache, cache.name == name { return cache.frames }
        guard let file = Self.folder?.appendingPathComponent(name, isDirectory: false),
              let data = try? Data(contentsOf: file),
              let frames = NotchCompanionImageSupport.frames(data) else { return nil }
        cache = (name, frames)
        return frames
    }

    /// Asks for a picture, keeps a copy and makes it the companion's, in
    /// place of the one before. False when the file is no picture that could
    /// be kept; nil when the person chose nothing.
    func choose(defaults: UserDefaults = .standard) -> Bool? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= NotchCompanionImageSupport.maximumBytes,
              let kept = (try? Data(contentsOf: url)).flatMap(NotchCompanionImageSupport.kept),
              let folder = Self.folder, PrivateFileStore.createDirectory(at: folder) else { return false }
        let name = UUID().uuidString.lowercased() + (kept.animated ? ".gif" : ".png")
        guard PrivateFileStore.write(kept.data, to: folder.appendingPathComponent(name, isDirectory: false)) else { return false }
        let previous = defaults.string(forKey: DefaultsKey.notchMascotCustomImage) ?? ""
        defaults.set(name, forKey: DefaultsKey.notchMascotCustomImage)
        if NotchCompanionImageSupport.isCompanionFile(previous) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(previous, isDirectory: false))
        }
        return true
    }
}
