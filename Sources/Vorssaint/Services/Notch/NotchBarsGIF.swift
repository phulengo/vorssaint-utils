// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO
import UniformTypeIdentifiers

enum NotchBarsGIFSupport {
    /// The largest file accepted when adding a GIF.
    static let maximumBytes = 16 * 1_024 * 1_024
    /// The GIF is drawn at most a few dozen points across, so its frames are
    /// kept at this size: a large GIF would otherwise be decoded at full size
    /// on every frame for the whole song.
    static let keptPixels = 128
    /// Frames past this are dropped from a very long GIF.
    static let maximumFrames = 600
    /// The collection lives beside the app's other private files, so a GIF
    /// keeps playing after the original moves or goes, and leaves with the
    /// app's data.
    static let folderName = "NotchMusicBars"
    /// Where a single chosen GIF was kept before the collection.
    static let earlierFileName = "NotchMusicBars.gif"

    /// Whether `data` is a GIF with at least one frame, small enough to keep.
    static func isGIF(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?,
              UTType(type)?.conforms(to: .gif) == true else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// Whether `name` is one of the collection's own files, so a name from
    /// anywhere else never leads outside the folder.
    static func isCollectionFile(_ name: String) -> Bool {
        name.hasSuffix(".gif") && !name.contains("/") && !name.hasPrefix(".") && name.count <= 64
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

/// The person's own GIFs for the place of the music bars beside the camera.
/// Every GIF added is shrunk to the size the island draws and kept in the
/// app's private folder, so any of them can be chosen again later; only those
/// copies are ever read. The chosen one is remembered by its file name.
final class NotchBarsGIF: ObservableObject {
    static let shared = NotchBarsGIF()

    struct Item: Identifiable, Equatable {
        /// The file's name in the collection.
        let id: String
        let data: Data
    }

    /// Oldest first.
    @Published private(set) var items: [Item] = []
    /// The chosen GIF's bytes, nil while the island draws its usual bars.
    /// Each view decodes its own image from them; see NotchBarsGIFView.
    @Published private(set) var data: Data?
    @Published private(set) var selection: String?

    private let defaults: UserDefaults

    private static var folder: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent(NotchBarsGIFSupport.folderName, isDirectory: true)
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        adoptEarlierFile()
        items = Self.loadItems()
        let chosen = defaults.string(forKey: DefaultsKey.notchMusicBarsGIF) ?? ""
        apply(selection: items.contains { $0.id == chosen } ? chosen : nil)
    }

    /// Asks for a GIF, keeps a copy in the collection and chooses it. False
    /// when the file chosen is no GIF the island can play, or could not be
    /// kept; nil when the person chose nothing.
    func add() -> Bool? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.gif]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= NotchBarsGIFSupport.maximumBytes,
              let kept = (try? Data(contentsOf: url)).flatMap(NotchBarsGIFSupport.kept),
              let name = Self.store(kept) else { return false }
        items.append(Item(id: name, data: kept))
        select(name)
        return true
    }

    /// Chooses a GIF from the collection, or the bars with nil.
    func select(_ id: String?) {
        apply(selection: id.flatMap { id in items.contains { $0.id == id } ? id : nil })
        defaults.set(selection ?? "", forKey: DefaultsKey.notchMusicBarsGIF)
    }

    /// Removes a GIF from the collection; the bars return if it was chosen.
    func delete(_ id: String) {
        guard NotchBarsGIFSupport.isCollectionFile(id) else { return }
        if let file = Self.folder?.appendingPathComponent(id, isDirectory: false) {
            try? FileManager.default.removeItem(at: file)
        }
        items.removeAll { $0.id == id }
        if selection == id { select(nil) }
    }

    private func apply(selection: String?) {
        self.selection = selection
        data = selection.flatMap { id in items.first { $0.id == id }?.data }
    }

    private static func loadItems() -> [Item] {
        guard let folder else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { NotchBarsGIFSupport.isCollectionFile($0.lastPathComponent) }
            .map { ($0, (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast) }
            .sorted { $0.1 < $1.1 }
            .compactMap { file, _ in
                guard let data = try? Data(contentsOf: file), NotchBarsGIFSupport.isGIF(data) else { return nil }
                return Item(id: file.lastPathComponent, data: data)
            }
    }

    /// Writes a kept GIF under a new name and returns that name.
    private static func store(_ data: Data) -> String? {
        guard let folder, PrivateFileStore.createDirectory(at: folder) else { return nil }
        let name = UUID().uuidString.lowercased() + ".gif"
        return PrivateFileStore.write(data, to: folder.appendingPathComponent(name, isDirectory: false)) ? name : nil
    }

    /// A GIF chosen before the collection existed joins it, still chosen.
    private func adoptEarlierFile() {
        guard let earlier = PrivateFileStore.containerURL?
                .appendingPathComponent(NotchBarsGIFSupport.earlierFileName, isDirectory: false),
              let data = try? Data(contentsOf: earlier) else { return }
        if NotchBarsGIFSupport.isGIF(data), let name = Self.store(data) {
            defaults.set(name, forKey: DefaultsKey.notchMusicBarsGIF)
        }
        try? FileManager.default.removeItem(at: earlier)
    }
}
