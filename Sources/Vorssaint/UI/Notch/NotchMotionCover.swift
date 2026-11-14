// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AVFoundation
import SwiftUI

/// The song's animated cover laid over its still one, while Apple has a video
/// for it and Reduce Motion is off. It belongs to the song it is drawn for, so
/// a strip still showing the previous song keeps that song's still cover. The
/// island's picture in Settings keeps the still cover, so a Settings window
/// kept around after closing never streams.
struct NotchMotionCover: View {
    let track: RadialNowPlayingSnapshot?
    @ObservedObject private var motion = NotchMotionArtwork.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.notchSettingsPreview) private var preview

    var body: some View {
        if !reduceMotion, !preview, let video = motion.video,
           video.key == NotchMotionArtworkSupport.songKey(for: track) {
            NotchMotionArtworkLayer(video: video.url)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct NotchMotionArtworkLayer: NSViewRepresentable {
    let video: URL

    func makeNSView(context: Context) -> NotchMotionArtworkView { NotchMotionArtworkView() }
    func updateNSView(_ view: NotchMotionArtworkView, context: Context) { view.showing = video }
    static func dismantleNSView(_ view: NotchMotionArtworkView, coordinator: ()) { view.release() }
}

/// Whether a view is on screen for someone to see: in a visible window that
/// nothing covers, and not hidden. The island orders its panel out or leaves
/// it covered without taking its views away, so being in a window is not enough.
private func notchViewIsExposed(_ view: NSView) -> Bool {
    !view.isHiddenOrHasHiddenAncestor && view.window?.isVisible == true
        && view.window?.occlusionState.contains(.visible) == true
}

/// Draws the shared player's frames. Each video fades in over the still cover
/// once its first frame is ready, so a cover never flashes black while the
/// stream loads. Only a view someone can see counts as showing the video.
final class NotchMotionArtworkView: NSView {
    private let playerLayer = AVPlayerLayer()
    private var ready: NSKeyValueObservation?
    private var occlusion: NSObjectProtocol?
    private var attached = false
    private var dismantled = false
    /// A new song's video starts hidden again until its own first frame.
    var showing: URL? {
        didSet { if showing != oldValue { playerLayer.opacity = 0 } }
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.opacity = 0
        layer?.addSublayer(playerLayer)
        ready = playerLayer.observe(\.isReadyForDisplay) { [weak self] _, _ in
            DispatchQueue.main.async { self?.reveal() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        if attached { NotchMotionArtwork.shared.player.detach() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = window.map {
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: $0,
                                                   queue: .main) { [weak self] _ in self?.updateExposure() }
        }
        updateExposure()
    }

    override func viewDidHide() { super.viewDidHide(); updateExposure() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateExposure() }

    /// The view leaves the island for good.
    func release() {
        dismantled = true
        updateExposure()
    }

    private func updateExposure() {
        let exposed = !dismantled && notchViewIsExposed(self)
        guard exposed != attached else { return }
        attached = exposed
        if exposed {
            playerLayer.player = NotchMotionArtwork.shared.player.player
            NotchMotionArtwork.shared.player.attach()
            reveal()
        } else {
            playerLayer.player = nil
            playerLayer.opacity = 0
            NotchMotionArtwork.shared.player.detach()
        }
    }

    private func reveal() {
        guard attached, playerLayer.isReadyForDisplay, playerLayer.opacity == 0 else { return }
        playerLayer.opacity = 1
    }
}

/// The person's GIF where the bars would be, scaled to fit its square. It
/// plays with the song and holds still while the song is paused, the play
/// button stands in its place or nobody can see it. Each view decodes its own
/// copy: views sharing one image would each advance the same frames, and the
/// GIF would run faster the more displays show it.
struct NotchBarsGIFView: NSViewRepresentable {
    let data: Data
    let animates: Bool

    func makeNSView(context: Context) -> NotchBarsGIFImageView {
        let view = NotchBarsGIFImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.imageFrameStyle = .none
        view.isEditable = false
        view.show(data)
        view.wantsAnimation = animates
        return view
    }

    func updateNSView(_ view: NotchBarsGIFImageView, context: Context) {
        view.show(data)
        view.wantsAnimation = animates
    }
}

/// Sized by the strip, never by the GIF, and transparent to the pointer so
/// the strip's own button and hover keep working over it.
final class NotchBarsGIFImageView: NSImageView {
    private var shown: Data?
    private var occlusion: NSObjectProtocol?
    var wantsAnimation = false { didSet { if wantsAnimation != oldValue { updateAnimation() } } }

    deinit { if let occlusion { NotificationCenter.default.removeObserver(occlusion) } }

    func show(_ data: Data) {
        guard data != shown else { return }
        shown = data
        image = NSImage(data: data)
        updateAnimation()
    }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = window.map {
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: $0,
                                                   queue: .main) { [weak self] _ in self?.updateAnimation() }
        }
        updateAnimation()
    }

    override func viewDidHide() { super.viewDidHide(); updateAnimation() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateAnimation() }

    private func updateAnimation() {
        let animating = wantsAnimation && notchViewIsExposed(self)
        if animates != animating { animates = animating }
    }
}
