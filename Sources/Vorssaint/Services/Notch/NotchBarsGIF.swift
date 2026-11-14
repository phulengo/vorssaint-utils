// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import UniformTypeIdentifiers

enum NotchBarsGIFSupport {
    /// The largest file accepted when choosing a GIF.
    static let maximumBytes = 16 * 1_024 * 1_024
    /// The GIF is drawn at most 26 points across, so its frames are kept at
    /// this size: a large GIF would otherwise be decoded at full size on every
    /// frame for the whole song.
    static let keptPixels = 128
    /// Frames past this are dropped from a very long GIF.
    static let maximumFrames = 600
    /// Kept beside the app's other private files, so the GIF keeps playing
    /// after the original moves or goes, and leaves with the app's data.
    static let fileName = "NotchMusicBars.gif"

    /// Whether `data` is a GIF with at least one frame, small enough to keep.
    static func isGIF(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              UTType(type)?.conforms(to: .gif) == true else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// The GIF as it is kept: every frame no larger than `keptPixels`, with
    /// its own delay and the file's loop count. Nil for anything else.
    static func kept(_ data: Data) -> Data? {
        guard isGIF(data), let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = min(CGImageSourceGetCount(source), maximumFrames)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.gif.identifier as CFString, count, nil)
        else { return nil }
        let file = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let loops = (file?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] ?? 0
        CGImageDestinationSetProperties(destination,
                                        [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loops]] as CFDictionary)
        let shrink = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: keptPixels] as CFDictionary
        for index in 0..<count {
            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, shrink) else { return nil }
            let gif = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])?[kCGImagePropertyGIFDictionary]
                as? [CFString: Any]
            let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] ?? gif?[kCGImagePropertyGIFDelayTime] ?? 0.1
            CGImageDestinationAddImage(destination, frame,
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}

/// The person's own GIF in place of the music bars beside the camera. The
/// file chosen is copied, shrunk to the size the island draws, into the
/// app's private folder, and only that copy is ever read.
final class NotchBarsGIF: ObservableObject {
    static let shared = NotchBarsGIF()

    /// Nil while the island draws its usual bars. Each view decodes its own
    /// image from these bytes; see NotchBarsGIFView.
    @Published private(set) var data: Data?

    private static var storedURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent(NotchBarsGIFSupport.fileName, isDirectory: false)
    }

    private init() {
        data = Self.storedURL.flatMap { try? Data(contentsOf: $0) }.flatMap { NotchBarsGIFSupport.isGIF($0) ? $0 : nil }
    }

    /// Asks for a GIF and keeps a copy of it. False when the file chosen is
    /// no GIF the island can play, or could not be kept; nil when the person
    /// chose nothing.
    func choose() -> Bool? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.gif]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= NotchBarsGIFSupport.maximumBytes,
              let kept = (try? Data(contentsOf: url)).flatMap(NotchBarsGIFSupport.kept),
              let container = PrivateFileStore.containerURL, let stored = Self.storedURL,
              PrivateFileStore.createDirectory(at: container), PrivateFileStore.write(kept, to: stored)
        else { return false }
        data = kept
        return true
    }

    /// Back to the bars.
    func remove() {
        if let stored = Self.storedURL { try? FileManager.default.removeItem(at: stored) }
        data = nil
    }
}
