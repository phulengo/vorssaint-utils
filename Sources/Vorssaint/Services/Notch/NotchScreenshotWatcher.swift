// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Tells the island when macOS saves a screenshot of its own, taken with its
/// shortcuts or the Screenshot app, so the companion reacts to it as to one
/// taken here. Spotlight marks those files; only that mark and when the
/// picture was taken are read, never the picture or where it is. One copied
/// to the clipboard leaves no file and goes unseen, one saved after its
/// floating thumbnail is seen as the thumbnail goes, and one saved where the
/// person did not let the app look is not reported to it.
final class NotchScreenshotWatcher {
    static let shared = NotchScreenshotWatcher()

    /// A screenshot Spotlight reports later than this after it was taken,
    /// as after the Mac wakes, is old news.
    static let freshness: TimeInterval = 30

    /// Called on the main thread when macOS has saved a new screenshot.
    var onScreenshot: (() -> Void)?

    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?

    private init() {}

    func sync(watching: Bool) {
        watching ? start() : stop()
    }

    private func start() {
        guard query == nil else { return }
        let query = NSMetadataQuery()
        // Only those taken from now on match, so its results stay few.
        query.predicate = NSPredicate(format: "%K == 1 AND %K >= %@", "kMDItemIsScreenCapture",
                                      "kMDItemContentCreationDate", Date() as NSDate)
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.notificationBatchingInterval = 0.25
        observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query,
                                                          queue: .main) { [weak self] note in
            self?.received(note)
        }
        self.query = query
        if !query.start() { stop(); return }
        // Spotlight reports a file only to an app allowed into its folder, and
        // macOS saves screenshots to the Desktop unless told otherwise. Looking
        // in once has macOS ask the person, the first time only; what is in
        // the folder is not kept or used.
        let location = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String
        let folder = CleanerSupport.screenshotFolder(location: location, home: NSHomeDirectory())
        DispatchQueue.global(qos: .utility).async {
            _ = try? FileManager.default.contentsOfDirectory(atPath: folder)
        }
    }

    private func stop() {
        query?.stop()
        query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func received(_ note: Notification) {
        guard let added = note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] else { return }
        let now = Date()
        let fresh = added.contains { item in
            // Only macOS records how a screenshot was taken. Ours, marked
            // as screenshots too, were reacted to as they were taken.
            guard item.value(forAttribute: "kMDItemScreenCaptureType") != nil,
                  let taken = item.value(forAttribute: "kMDItemContentCreationDate") as? Date else { return false }
            return now.timeIntervalSince(taken) < Self.freshness
        }
        if fresh { onScreenshot?() }
    }
}
