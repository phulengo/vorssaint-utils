// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The companion's line as a subtitle: a small black pill hanging just under
/// the island, as the translator's English under Rocky's chords, for as long
/// as the line is said. Its own borderless window, which clicks pass through,
/// so the island's window keeps its size.
final class NotchMascotCaption {
    let window: NSPanel
    private let pill = NSView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private var hideWork: DispatchWorkItem?

    static let maximumWidth: CGFloat = 320
    static let padding = CGSize(width: 12, height: 6)
    /// The gap between the island and the line under it.
    static let gap: CGFloat = 5

    init() {
        // Made at once, not deferred: the island's Space takes in only a
        // window the window server already numbered.
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.alphaValue = 0
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor.black.cgColor
        pill.layer?.cornerCurve = .continuous
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = NSColor.white.withAlphaComponent(0.92)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.isSelectable = false
        pill.addSubview(label)
        window.contentView = pill
    }

    /// Shows `text` centred under `island`, a frame on screen, for `duration`.
    func show(_ text: String, under island: CGRect, level: NSWindow.Level, behavior: NSWindow.CollectionBehavior,
              duration: TimeInterval, reduceMotion: Bool) {
        hideWork?.cancel()
        label.stringValue = text
        let inner = Self.maximumWidth - Self.padding.width * 2
        let fits = label.cell?.cellSize(forBounds: CGRect(x: 0, y: 0, width: inner, height: 200)) ?? CGSize(width: inner, height: 16)
        let textSize = CGSize(width: min(inner, ceil(fits.width)), height: ceil(fits.height))
        let size = CGSize(width: textSize.width + Self.padding.width * 2, height: textSize.height + Self.padding.height * 2)
        let frame = CGRect(x: (island.midX - size.width / 2).rounded(), y: (island.minY - Self.gap - size.height).rounded(),
                           width: size.width, height: size.height)
        window.level = level
        window.collectionBehavior = behavior
        window.setFrame(frame, display: false)
        label.frame = CGRect(origin: CGPoint(x: Self.padding.width, y: Self.padding.height), size: textSize)
        pill.layer?.cornerRadius = min(size.height / 2, 11)
        window.orderFrontRegardless()
        fade(to: 1, duration: reduceMotion ? 0 : 0.18)
        let work = DispatchWorkItem { [weak self] in self?.hide(reduceMotion: reduceMotion) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// Keeps a line on screen hanging under `island` as the island changes
    /// shape, as when a screenshot's preview opens it just after he speaks.
    func follow(_ island: CGRect, reduceMotion: Bool) {
        guard window.isVisible, hideWork != nil else { return }
        let size = window.frame.size
        let frame = CGRect(x: (island.midX - size.width / 2).rounded(), y: (island.minY - Self.gap - size.height).rounded(),
                           width: size.width, height: size.height)
        guard frame != window.frame else { return }
        guard !reduceMotion else { window.setFrame(frame, display: true); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    func hide(reduceMotion: Bool = false) {
        hideWork?.cancel()
        hideWork = nil
        guard window.isVisible else { return }
        fade(to: 0, duration: reduceMotion ? 0 : 0.25) { [weak self] in
            guard let self, self.hideWork == nil else { return }
            self.window.orderOut(nil)
        }
    }

    private func fade(to alpha: CGFloat, duration: TimeInterval, completion: (() -> Void)? = nil) {
        guard duration > 0 else {
            window.alphaValue = alpha
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            window.animator().alphaValue = alpha
        }, completionHandler: completion)
    }
}
