// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// Rocky out of the island for a show. Clicked where he performs in the
/// closed island, he leaps out under it, grown to the size of a pet on the
/// desktop: he waves hello, plays one of his acts and bows goodbye, saying a
/// line with each as in the film, then shrinks back into his place. His
/// lines show under his feet while his subtitles are on, and are said aloud
/// while his voice is. A click on him sends him back early. His own
/// borderless window, which takes no focus; the small Rocky in the island
/// waits hidden meanwhile.
final class NotchMascotShowtime {
    static let shared = NotchMascotShowtime()

    private var window: NSPanel?
    private var zoom: CALayer?
    private var rig: NotchMascotRig?
    private var caption: NotchMascotShowtimeCaption?
    private var steps: [DispatchWorkItem] = []
    private var finished: (() -> Void)?
    /// Where he came from, on screen, to go back to.
    private var origin = CGRect.zero
    private var round = 0

    var isShowing: Bool { window != nil }

    /// Begins a show for Rocky standing at `small` on screen, in a strip
    /// whose foot is at `stripBottom`, on `screen`. `finished` runs once he
    /// is back, to show the small one again.
    func begin(look: NotchMascotLook, from small: CGRect, stripBottom: CGFloat, screen: CGRect,
               level: NSWindow.Level, behavior: NSWindow.CollectionBehavior, scale: CGFloat,
               defaults: UserDefaults = .standard, finished: @escaping () -> Void) {
        guard !isShowing, small.width > 0 else { finished(); return }
        let size = NotchMascotSupport.showtimeSize
        let frame = NotchMascotSupport.showtimeFrame(size: size, under: stripBottom, near: small.midX, screen: screen)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = level
        panel.collectionBehavior = behavior
        let content = NotchMascotShowtimeView(frame: CGRect(origin: .zero, size: frame.size))
        content.onClick = { [weak self] in self?.end() }
        panel.contentView = content

        // His stage, a square over the room for his lines, flipped as the
        // island's: it grows him from his place.
        let side = frame.width
        let zoom = CALayer()
        zoom.isGeometryFlipped = true
        zoom.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        zoom.position = CGPoint(x: side / 2, y: frame.height - side / 2)
        let rig = NotchMascotRig()
        rig.configure(look: look, size: size, contentsScale: scale)
        let shift = NotchMascotGeometry.figureOffset(look) * size
        rig.root.position = CGPoint(x: side / 2, y: side / 2 - shift)
        zoom.addSublayer(rig.root)
        content.layer?.addSublayer(zoom)
        let caption = NotchMascotShowtimeCaption(frame: CGRect(x: 0, y: 0, width: frame.width,
                                                               height: NotchMascotSupport.showtimeCaptionRoom))
        content.addSubview(caption)

        self.window = panel
        self.zoom = zoom
        self.rig = rig
        self.caption = caption
        self.finished = finished
        self.origin = small
        panel.orderFrontRegardless()

        // Out of his place in the island, as big as a pet on the desktop.
        let grow = CASpringAnimation(keyPath: "transform")
        grow.fromValue = NSValue(caTransform3D: transform(toward: small, in: frame, size: size))
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        grow.damping = 14
        grow.stiffness = 170
        grow.mass = 1
        grow.duration = grow.settlingDuration
        zoom.add(grow, forKey: "grow")

        // Hello, an act, goodbye: each beat lasts as long as its act or its
        // line, whichever is longer, so a line is never cut off.
        let subtitles = defaults.bool(forKey: DefaultsKey.notchMascotSubtitles)
        var at = 0.45
        for beat in NotchMascotPuppetMotion.showtime(round: round) {
            let length = max(beat.act.track.duration, NotchMascotSpeech.shared.length(of: beat.line, defaults: defaults))
            schedule(after: at) { [weak self, weak rig] in
                rig?.play(act: beat.act)
                let said = NotchMascotSpeech.shared.perform(beat.line, defaults: defaults)
                if subtitles { self?.caption?.show(beat.line.text, for: max(said + 0.3, beat.act.track.duration)) }
            }
            at += length + 0.2
        }
        round += 1
        schedule(after: at) { [weak self] in self?.end() }
    }

    /// Sends him back into the island now.
    func end() {
        guard let window, let zoom else { return }
        steps.forEach { $0.cancel() }
        steps = []
        caption?.hide()
        let back = transform(toward: origin, in: window.frame, size: NotchMascotSupport.showtimeSize)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.close() }
        let shrink = CABasicAnimation(keyPath: "transform")
        shrink.fromValue = NSValue(caTransform3D: zoom.presentation()?.transform ?? CATransform3DIdentity)
        shrink.toValue = NSValue(caTransform3D: back)
        shrink.duration = 0.34
        shrink.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0.2)
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        zoom.add(shrink, forKey: "shrink")
        CATransaction.commit()
        // A second chance at closing, should the animation never report back.
        schedule(after: 0.6) { [weak self] in self?.close() }
    }

    private func close() {
        guard let window else { return }
        steps.forEach { $0.cancel() }
        steps = []
        window.orderOut(nil)
        window.contentView = nil
        self.window = nil
        zoom = nil
        rig = nil
        caption = nil
        let finished = self.finished
        self.finished = nil
        finished?()
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        let work = DispatchWorkItem(block: action)
        steps.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// The transform that puts the big Rocky, on his stage at the top of
    /// `frame`, over `target` on screen, at its size.
    private func transform(toward target: CGRect, in frame: CGRect, size: CGFloat) -> CATransform3D {
        let scale = max(0.05, target.width / size)
        let stage = CGPoint(x: frame.midX, y: frame.maxY - frame.width / 2)
        return CATransform3DConcat(CATransform3DMakeScale(scale, scale, 1),
                                   CATransform3DMakeTranslation(target.midX - stage.x, target.midY - stage.y, 0))
    }
}

/// The show's window content: a click on him sends him back.
private final class NotchMascotShowtimeView: NSView {
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer = CALayer()
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// What he says on a show, as the translator's subtitle under his feet:
/// white on a black pill, as under the island.
private final class NotchMascotShowtimeCaption: NSView {
    private let pill = NSView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private var hideWork: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        pill.layer?.cornerCurve = .continuous
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.92)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.isSelectable = false
        pill.addSubview(label)
        addSubview(pill)
        alphaValue = 0
    }

    required init?(coder: NSCoder) { nil }

    func show(_ text: String, for duration: TimeInterval) {
        hideWork?.cancel()
        label.stringValue = text
        let inner = bounds.width - 32
        let fits = label.cell?.cellSize(forBounds: CGRect(x: 0, y: 0, width: inner, height: 60)) ?? CGSize(width: inner, height: 16)
        let text = CGSize(width: min(inner, ceil(fits.width)), height: min(bounds.height - 8, ceil(fits.height)))
        let size = CGSize(width: text.width + 20, height: text.height + 10)
        pill.frame = CGRect(x: (bounds.width - size.width) / 2, y: bounds.height - size.height - 2, width: size.width, height: size.height)
        pill.layer?.cornerRadius = min(size.height / 2, 11)
        label.frame = CGRect(x: 10, y: 5, width: text.width, height: text.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = 1
        }
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func hide() {
        hideWork?.cancel()
        hideWork = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = 0
        }
    }
}
