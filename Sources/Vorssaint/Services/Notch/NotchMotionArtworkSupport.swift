// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Apple Music gives some albums a short looping video in place of the
/// cover. Apple's public catalog search names the album of a song, and the
/// album's own page on music.apple.com carries the address of that video,
/// a muted HLS stream, when the album has one. Most albums have none, and
/// then the still cover stays.
enum NotchMotionArtworkSupport {
    /// The lookup goes online, so it waits for its own option in the music
    /// settings, which starts off.
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && defaults.bool(forKey: DefaultsKey.notchMotionCovers)
    }

    /// What one song's lookup goes by, or nil when it has none to run. A title
    /// alone would match other songs, so the artist is required, and the album
    /// keeps a single apart from the album that holds the video.
    static func lookupKey(for track: RadialNowPlayingSnapshot?, defaults: UserDefaults = .standard) -> String? {
        guard isEnabled(in: defaults), let track else { return nil }
        return songKey(for: track)
    }

    /// The song a cover belongs to, whatever the option says, so a strip that
    /// still shows the previous song never plays the next song's video.
    static func songKey(for track: RadialNowPlayingSnapshot?) -> String? {
        func cleaned(_ text: String?) -> String? {
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return text
        }
        guard let title = cleaned(track?.title), let artist = cleaned(track?.artist) else { return nil }
        return [artist, title, cleaned(track?.album) ?? ""].joined(separator: "\n")
    }

    /// Album pages tried per song. Another edition of the same album often
    /// carries the video the first one lacks, and every page is about half a
    /// megabyte, well under the download's 4 MB bound.
    static let maximumAlbumPages = 2

    /// The album pages of the results whose title and artist match the song,
    /// best first: the album that names the song's own album leads, then
    /// Apple's ranking. Only pages on music.apple.com take part, each album
    /// once. The address keeps the query the search gave it, since the plain
    /// album address redirects and the download refuses redirects.
    static func albumPageURLs(inSearch json: Data, title: String, artist: String?, album: String?) -> [URL] {
        let matches = NotchBrowserArtworkSupport.appleMusicMatches(inSearch: json, title: title, artist: artist)
        let wantedAlbum = album.map(NotchBrowserArtworkSupport.folded).flatMap { $0.isEmpty ? nil : $0 }
        let ranked = matches.enumerated().sorted { first, second in
            let firstNamed = wantedAlbum != nil && (first.element["collectionName"] as? String)
                .map(NotchBrowserArtworkSupport.folded) == wantedAlbum
            let secondNamed = wantedAlbum != nil && (second.element["collectionName"] as? String)
                .map(NotchBrowserArtworkSupport.folded) == wantedAlbum
            return firstNamed != secondNamed ? firstNamed : first.offset < second.offset
        }
        var seen = Set<String>()
        var pages: [URL] = []
        for (_, match) in ranked {
            guard let address = match["collectionViewUrl"] as? String, let url = URL(string: address),
                  url.scheme?.lowercased() == "https", url.host?.lowercased() == "music.apple.com",
                  url.pathComponents.contains("album") else { continue }
            let album = (match["collectionId"] as? NSNumber)?.stringValue ?? url.path
            guard seen.insert(album).inserted else { continue }
            pages.append(url)
            if pages.count == maximumAlbumPages { break }
        }
        return pages
    }

    /// The album a page shows, by Apple's album number, the same whichever
    /// of its songs led there.
    static func albumKey(for page: URL) -> String { page.lastPathComponent }

    /// The square looping video of the album a page shows, or nil when it has
    /// none. The page carries its data as JSON in one script element. Only the
    /// first item that lists a video slot counts, which is the album itself:
    /// the albums the page suggests below never stand in for it. The stream
    /// loads only from Apple's own video servers, whatever the page names.
    static func motionVideoURL(inAlbumPage page: Data) -> URL? {
        guard let html = String(data: page, encoding: .utf8),
              let open = html.range(of: #"<script[^>]*id="serialized-server-data"[^>]*>"#, options: .regularExpression),
              let close = html.range(of: "</script>", range: open.upperBound..<html.endIndex),
              let root = try? JSONSerialization.jsonObject(with: Data(html[open.upperBound..<close.lowerBound].utf8))
        else { return nil }
        let entries = (root as? [String: Any]).map { [$0] } ?? (root as? [[String: Any]]) ?? []
        let shelves = entries.flatMap { entry -> [[String: Any]] in
            let pages = entry["data"] as? [[String: Any]] ?? []
            return pages.flatMap { ($0["data"] as? [String: Any])?["sections"] as? [[String: Any]] ?? [] }
        }
        guard let header = shelves.lazy.flatMap({ $0["items"] as? [[String: Any]] ?? [] })
                .first(where: { $0.keys.contains("videoArtwork") }),
              let artwork = header["videoArtwork"] as? [String: Any],
              let square = (artwork["dictionary"] as? [String: Any])?["motionDetailSquare"] as? [String: Any],
              let address = square["video"] as? String, let video = URL(string: address),
              video.scheme?.lowercased() == "https",
              video.host?.lowercased() == "mvod.itunes.apple.com",
              video.pathExtension.lowercased() == "m3u8" else { return nil }
        return video
    }
}
