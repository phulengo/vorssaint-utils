// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AVFoundation
import Foundation
import QuartzCore

/// Rocky says a line when he reacts, when he sets out on a stroll and when
/// he dozes off: its text shows under the island while his subtitles are on,
/// and once the person turns his voice on, he says it aloud too, his chords
/// and the translator's English in one recording. Everything here runs on
/// the main thread.
final class NotchMascotSpeech {
    static let shared = NotchMascotSpeech()

    /// Shows a line's text under the island for about as long as it is said;
    /// the island's window sets it.
    var showLine: ((String, TimeInterval) -> Void)?

    private var gate = NotchMascotLineGate()
    private var player: AVAudioPlayer?

    /// Tells which line a reaction about to play stands for, when other
    /// moments share it: the next time he plays it, within `within`. Asked
    /// without one, the reaction says its own line, whatever an earlier
    /// request that never played had cued.
    func cue(_ line: NotchMascotLine?, for reaction: NotchMascotReaction, within: TimeInterval) {
        gate.cue(line, for: reaction, until: CACurrentMediaTime() + within)
    }

    func react(_ reaction: NotchMascotReaction, defaults: UserDefaults = .standard) {
        guard let line = gate.line(for: reaction, at: CACurrentMediaTime()) else { return }
        say(line, defaults: defaults)
    }

    /// One of his own lines, said only now and then.
    func ambient(_ lines: [NotchMascotLine], defaults: UserDefaults = .standard) {
        guard let line = gate.ambient(lines, at: CACurrentMediaTime()) else { return }
        say(line, defaults: defaults)
    }

    /// Says `line` on a show out of the island, which shows its own text:
    /// aloud if his voice is on. Returns about how long it takes.
    @discardableResult
    func perform(_ line: NotchMascotLine, defaults: UserDefaults = .standard) -> TimeInterval {
        play(line, defaults: defaults) ?? line.readingTime
    }

    /// About how long `line` takes: its recording while his voice is on,
    /// the time to read it otherwise.
    func length(of line: NotchMascotLine, defaults: UserDefaults = .standard) -> TimeInterval {
        guard defaults.bool(forKey: DefaultsKey.notchMascotVoice),
              let url = Bundle.main.resourceURL?.appending(path: "Companion/Rocky/" + line.file),
              let recording = try? AVAudioPlayer(contentsOf: url) else { return line.readingTime }
        return max(line.readingTime, recording.duration + 0.3)
    }

    func stop() {
        player?.stop()
        player = nil
    }

    private func say(_ line: NotchMascotLine, defaults: UserDefaults) {
        // The translation comes after his chords; the text stays until it ends.
        let length = max(line.readingTime, (play(line, defaults: defaults) ?? 0) + 0.6)
        if defaults.bool(forKey: DefaultsKey.notchMascotSubtitles) { showLine?(line.text, length) }
    }

    /// Plays `line`'s recording while his voice is on; its length, or nil.
    private func play(_ line: NotchMascotLine, defaults: UserDefaults) -> TimeInterval? {
        guard defaults.bool(forKey: DefaultsKey.notchMascotVoice),
              let url = Bundle.main.resourceURL?.appending(path: "Companion/Rocky/" + line.file),
              let next = try? AVAudioPlayer(contentsOf: url) else { return nil }
        player?.stop()
        next.volume = 0.85
        next.play()
        player = next
        return next.duration
    }
}
