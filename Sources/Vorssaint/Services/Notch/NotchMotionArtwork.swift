// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import Combine
import Foundation

/// Finds the animated cover of the song playing now; see
/// NotchMotionArtworkSupport. It follows the music service by itself, so it
/// starts with the first cover that could show a video and needs nothing from
/// the player's readings. With Reduce Motion on, no cover moves, so nothing is
/// looked up. Answers stay in memory for the last few songs and albums,
/// including the many albums without a video, and nothing is written to disk.
final class NotchMotionArtwork: ObservableObject {
    static let shared = NotchMotionArtwork()

    struct Video: Equatable {
        /// The song it belongs to; see NotchMotionArtworkSupport.songKey.
        let key: String
        let url: URL
    }

    /// The video of the song playing now, nil while it is looked up or when
    /// the song has none.
    @Published private(set) var video: Video?
    let player = NotchMotionArtworkPlayer()

    private static let rememberedAnswers = 32
    /// A lookup the network cut short is tried again after this long.
    private static let failureCooldown: TimeInterval = 60
    /// Album pages are parsed here, never on the main thread.
    private static let parsing = DispatchQueue(label: "com.vorssaint.notch-motion-artwork", qos: .utility)

    /// By song, then by album page: the next song of an album already read
    /// needs only its search.
    private var answers = NotchMotionAnswers()
    private var pageAnswers = NotchMotionAnswers()
    private var failedAt: [String: Date] = [:]
    private var wanted: String?
    private var generation = UUID()
    private var download: URLSession?
    private var retryWork: DispatchWorkItem?
    private var subscriptions: [AnyCancellable] = []

    private init() {
        // The publisher sends the value being set, before the service holds it.
        NotchMusicService.shared.$playback.sink { [weak self] in self?.update($0) }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.sync() }
            .store(in: &subscriptions)
    }

    /// The option in Settings or Reduce Motion changed.
    func sync() { update(NotchMusicService.shared.playback) }

    private func update(_ playback: NotchPlayback?) {
        player.setPlaying(playback?.isPlaying == true)
        let key = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil
            : NotchMotionArtworkSupport.lookupKey(for: playback?.track)
        guard key != wanted else { return }
        cancel()
        wanted = key
        guard let key, let track = playback?.track, let title = track.title else { return publish(nil) }
        if let answer = answers[key] { return publish(answer.map { Video(key: key, url: $0) }) }
        publish(nil)
        if let failed = failedAt[key], Date().timeIntervalSince(failed) < Self.failureCooldown {
            return retry(after: failed.addingTimeInterval(Self.failureCooldown).timeIntervalSinceNow)
        }
        guard let search = NotchBrowserArtworkSupport.appleMusicSearchURL(
            title: title, artist: track.artist, country: Locale.current.region?.identifier) else { return }
        let requested = generation
        load(search, accept: "application/json", requested, parse: {
            $0.map { NotchMotionArtworkSupport.albumPageURLs(inSearch: $0, title: title, artist: track.artist,
                                                             album: track.album) }
        }) { [weak self] pages in
            guard let self else { return }
            guard let pages else { return self.fail(key) }
            self.loadPages(pages, key: key, requested)
        }
    }

    /// Each album page in turn until one has a video. Running out of pages is
    /// an answer; a page that did not load is not.
    private func loadPages(_ pages: [URL], key: String, _ requested: UUID) {
        guard let page = pages.first else { return answer(nil, for: key) }
        let album = NotchMotionArtworkSupport.albumKey(for: page)
        if let known = pageAnswers[album] {
            if let video = known { return answer(video, for: key) }
            return loadPages(Array(pages.dropFirst()), key: key, requested)
        }
        load(page, accept: "text/html", requested, parse: {
            $0.map { NotchMotionArtworkSupport.motionVideoURL(inAlbumPage: $0) }
        }) { [weak self] video in
            guard let self else { return }
            guard let video else { return self.fail(key) }
            self.pageAnswers[album] = .some(video)
            if let video { return self.answer(video, for: key) }
            self.loadPages(Array(pages.dropFirst()), key: key, requested)
        }
    }

    /// The reply is read on the parsing queue; the result comes back to the
    /// main thread and continues only for the lookup that asked, while the
    /// option is still on.
    private func load<Value>(_ url: URL, accept: String, _ requested: UUID, parse: @escaping (Data?) -> Value?,
                             completion: @escaping (Value?) -> Void) {
        guard generation == requested, NotchMotionArtworkSupport.isEnabled() else { return }
        download = NotchBrowserArtworkDownload.load(url, accept: accept) { data in
            Self.parsing.async {
                let result = parse(data)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == requested, NotchMotionArtworkSupport.isEnabled() else { return }
                    self.download = nil
                    completion(result)
                }
            }
        }
    }

    private func answer(_ url: URL?, for key: String) {
        answers[key] = .some(url)
        if wanted == key { publish(url.map { Video(key: key, url: $0) }) }
    }

    /// The song is tried again once the cooldown ends, if it still plays.
    private func fail(_ key: String) {
        let now = Date()
        failedAt = failedAt.filter { now.timeIntervalSince($0.value) < Self.failureCooldown }
        failedAt[key] = now
        retry(after: Self.failureCooldown)
    }

    private func retry(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.retryWork = nil
            self.wanted = nil
            self.sync()
        }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(1, delay), execute: work)
    }

    private func cancel() {
        generation = UUID()
        download?.invalidateAndCancel()
        download = nil
        retryWork?.cancel()
        retryWork = nil
    }

    private func publish(_ video: Video?) {
        player.show(video?.url)
        if self.video != video { self.video = video }
    }
}

/// A bounded memory of lookups, oldest forgotten first. A stored nil is an
/// answer too: the album has no video.
struct NotchMotionAnswers {
    private var answers: [String: URL?] = [:]
    private var order: [String] = []

    subscript(key: String) -> URL?? {
        get { answers[key] }
        set {
            answers[key] = newValue
            order.removeAll { $0 == key }
            guard newValue != nil else { return }
            order.append(key)
            while order.count > 32 { answers[order.removeFirst()] = nil }
        }
    }
}

/// One muted player for the animated cover, shared by every cover that shows
/// it, so the strip, the open island and a copy on another display draw the
/// same frames from one stream. It plays only while a cover someone can see
/// shows it and the song plays, and holds its frame through a pause. Once no
/// cover shows it, the stream stays loaded a little while, so reopening the
/// island or the next song of the same album does not load it again. The
/// whole loop loads once and replays from memory. The video has no sound,
/// sends no cookies, never keeps the display awake and never goes to AirPlay.
final class NotchMotionArtworkPlayer {
    /// The island draws a cover at most 56 points across. The stream offers
    /// squares from 360 pixels up, and these keep it to the smallest.
    private static let largestFrame = CGSize(width: 480, height: 480)
    private static let peakBitRate: Double = 300_000
    private static let unloadDelay: TimeInterval = 15

    private(set) lazy var player: AVPlayer = {
        let player = AVPlayer()
        player.isMuted = true
        player.allowsExternalPlayback = false
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .none
        return player
    }()
    private var viewers = 0
    private var video: URL?
    private var loaded: URL?
    private var playing = false
    private var loop: NSObjectProtocol?
    private var unload: DispatchWorkItem?

    func attach() { viewers += 1; refresh() }
    func detach() { viewers = max(0, viewers - 1); refresh() }
    func show(_ video: URL?) { self.video = video; refresh() }
    func setPlaying(_ playing: Bool) { self.playing = playing; refresh() }

    private func refresh() {
        let wanted = viewers > 0 ? video : nil
        if let wanted, wanted != loaded { load(wanted) }
        if wanted != nil || loaded == nil {
            unload?.cancel()
            unload = nil
        } else if unload == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.unload = nil
                self?.load(nil)
            }
            unload = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.unloadDelay, execute: work)
        }
        guard loaded != nil else { return }
        let rate: Float = wanted != nil && playing ? 1 : 0
        guard player.rate != rate else { return }
        if rate > 0 { player.play() } else { player.pause() }
    }

    private func load(_ video: URL?) {
        loaded = video
        if let loop { NotificationCenter.default.removeObserver(loop) }
        loop = nil
        guard let video else { return player.replaceCurrentItem(with: nil) }
        let item = AVPlayerItem(asset: AVURLAsset(url: video, options: [AVURLAssetHTTPCookiesKey: [HTTPCookie]()]))
        item.preferredMaximumResolution = Self.largestFrame
        item.preferredPeakBitRate = Self.peakBitRate
        player.replaceCurrentItem(with: item)
        // The video is made to loop, so its end leads straight back to its start.
        loop = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item,
                                                      queue: .main) { [weak self] _ in
            self?.player.seek(to: .zero)
        }
    }
}
