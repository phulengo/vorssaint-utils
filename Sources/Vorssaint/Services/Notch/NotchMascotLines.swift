// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Rocky's lines: what he says, in the translator's English, for each moment
/// he reacts to, for a stroll and for dozing off. Each recording holds both
/// of his voices, his chords first and the translation after, recorded for
/// this app; the text shows under the island as he says it.
enum NotchMascotLine: String, CaseIterable {
    case fist, amaze, bad, count, timedone, meeting, light, sing, listen, quiet, back, rest, watchdone, good, energy, fix,
         walk, search = "where", make, sleep
    /// A show out of the island: hello, one for each of his acts, and goodbye.
    case showHello = "show-hello", showTap = "show-tap", showStretch = "show-stretch", showLook = "show-look",
         showHammer = "show-hammer", showDance = "show-dance", showBye = "show-bye"

    var text: String {
        switch self {
        case .fist: return "Fist my bump."
        case .amaze: return "Amaze! Amaze! Amaze!"
        case .bad: return "Bad, bad, bad. Try again, question?"
        case .count: return "I count. Friend work."
        case .timedone: return "Time is done, done, done!"
        case .meeting: return "Friend go now. Meeting is soon."
        case .light: return "Light picture, question? I not see."
        case .sing: return "Friend machine sing! Good chords."
        case .listen: return "I listen. Speak, friend."
        case .quiet: return "Quiet now. Understand."
        case .back: return "Friend is back! Happy, happy, happy!"
        case .rest: return "Friend rest. I watch."
        case .watchdone: return "Watch is done. Now sleep, question?"
        case .good: return "Is good feeling. More, question?"
        case .energy: return "Energy low, low, low. Feed machine, friend."
        case .fix: return "Is engineering problem. I fix."
        case .walk: return "I walk. Friend follow, question?"
        case .search: return "Where, where, where. I find."
        case .make: return "Is quiet. I make thing."
        case .sleep: return "I sleep. Friend watch, question?"
        case .showHello: return "Friend! Watch, watch, watch!"
        case .showTap: return "Tap, tap, tap! Is rock music."
        case .showStretch: return "Long day. Legs need stretch, stretch."
        case .showLook: return "Big screen! Many window, many thing."
        case .showHammer: return "Build, build, build! Is good work."
        case .showDance: return "Dance, dance, dance! Is happy chords."
        case .showBye: return "Show is done. I go home, friend."
        }
    }

    /// What he says on his shows out of the island, in the order they come.
    static let showLines: [NotchMascotLine] = [.showHello, .showTap, .showStretch, .showLook, .showHammer, .showDance, .showBye]

    /// Its recording, in the companion's resources.
    var file: String { "voice-\(rawValue).mp3" }

    /// How long its text stays up without his voice: long enough to read.
    var readingTime: TimeInterval { max(2.4, 0.9 + Double(text.count) * 0.055) }

    /// What he says for a reaction when nothing more is known of its cause.
    static func line(for reaction: NotchMascotReaction) -> NotchMascotLine {
        switch reaction {
        case .celebrate: return .fist
        case .love: return .good
        case .surprised: return .timedone
        case .flash: return .light
        case .confused: return .bad
        case .wakeUp: return .back
        case .yawn: return .watchdone
        case .perk: return .listen
        case .bounce: return .meeting
        case .hush: return .quiet
        case .ready: return .count
        case .groove: return .sing
        }
    }

    /// What he may say setting out on a stroll around the island, taking
    /// turns, or coming home from the Command Bar. Crossing over what the
    /// island shows, as an agent's work, he keeps quiet: that is the
    /// person's to read.
    static func lines(for visit: NotchMascotVisit.Kind) -> [NotchMascotLine] {
        switch visit {
        case .lap: return [.walk, .search]
        case .home: return [.make]
        default: return []
        }
    }

    /// What he says for a moment, as Settings lists it: each cause in turn
    /// where the moment has more than one, as an agent starting and finishing.
    static func lines(for moment: NotchMascotMoment) -> [NotchMascotLine] {
        switch moment {
        case .visit: return lines(for: .lap) + lines(for: .home)
        case .agents: return [.fix, .fist]
        case .micMuted: return [.quiet, .listen]
        case .keepAwake: return [.rest, .watchdone]
        default: return moment.reaction.map { [moment.line ?? line(for: $0)] } ?? []
        }
    }
}

extension NotchMascotMoment {
    /// The line for a moment whose reaction other moments share, told apart
    /// by what caused it; nil where the reaction's own line fits.
    var line: NotchMascotLine? {
        switch self {
        case .downloadFinished: return .amaze
        case .keepAwake: return .rest
        case .lowBattery: return .energy
        case .agents: return .fix
        default: return nil
        }
    }
}

/// Which line Rocky says, and when he keeps quiet. Times are on the media
/// clock, in seconds.
struct NotchMascotLineGate {
    /// A reaction played again this soon is the same moment shown twice,
    /// as by the island and its preview, or by the strip and the window's
    /// own layer as the island changes shape: it is said once.
    static let echo: TimeInterval = 1
    /// Lines of his own, on a stroll or dozing off, come no sooner than this
    /// after any other line, and the same one no sooner than `ambientRepeat`.
    static let ambientSpacing: TimeInterval = 600
    static let ambientRepeat: TimeInterval = 1_800
    /// A line said as its moment happens comes back no sooner than this, so
    /// a burst of screenshots is one line, not one each.
    static let aheadRepeat: TimeInterval = 10

    private var cues: [NotchMascotReaction: (line: NotchMascotLine, until: TimeInterval)] = [:]
    private var lastReaction: (reaction: NotchMascotReaction, at: TimeInterval)?
    private var lastSaid = -TimeInterval.infinity
    private var ambientSaid: [NotchMascotLine: TimeInterval] = [:]
    /// Reactions whose line was said as their moment happened: when it was,
    /// and until when his playing it says nothing more.
    private var saidAhead: [NotchMascotReaction: (at: TimeInterval, holds: TimeInterval)] = [:]

    /// The cause of a reaction about to play, told by what asked for it:
    /// the next time he plays `reaction`, until `until`, he says `line`. The
    /// latest request decides, so nil leaves the reaction its own line.
    mutating func cue(_ line: NotchMascotLine?, for reaction: NotchMascotReaction, until: TimeInterval) {
        cues[reaction] = line.map { ($0, until) }
    }

    /// The line for `reaction` played at `now`, or nil for an echo of one just said.
    mutating func line(for reaction: NotchMascotReaction, at now: TimeInterval) -> NotchMascotLine? {
        // Said already as its moment happened: playing it now only shows it.
        if let ahead = saidAhead[reaction], now <= ahead.holds {
            saidAhead[reaction]?.holds = -.infinity
            cues[reaction] = nil
            lastReaction = (reaction, now)
            return nil
        }
        if let last = lastReaction, last.reaction == reaction, now - last.at < Self.echo { return nil }
        lastReaction = (reaction, now)
        var line = NotchMascotLine.line(for: reaction)
        if let cue = cues.removeValue(forKey: reaction), now <= cue.until { line = cue.line }
        lastSaid = now
        return line
    }

    /// The line for `reaction`, said as its moment happens at `now` whether
    /// or not he can be seen playing it, as when a screenshot's preview takes
    /// the island at once; nil within `aheadRepeat` of saying it so before.
    /// Either way, his playing it until `holds` says nothing more.
    mutating func lineAhead(for reaction: NotchMascotReaction, at now: TimeInterval,
                            holds: TimeInterval) -> NotchMascotLine? {
        if let ahead = saidAhead[reaction], now - ahead.at < Self.aheadRepeat {
            saidAhead[reaction] = (ahead.at, holds)
            cues[reaction] = nil
            return nil
        }
        saidAhead[reaction] = nil
        guard let line = line(for: reaction, at: now) else { return nil }
        saidAhead[reaction] = (now, holds)
        return line
    }

    /// The one of `lines`, his own, said longest ago, if one may be said at
    /// `now`; else nil.
    mutating func ambient(_ lines: [NotchMascotLine], at now: TimeInterval) -> NotchMascotLine? {
        guard now - lastSaid >= Self.ambientSpacing,
              let line = lines.filter({ now - (ambientSaid[$0] ?? -.infinity) >= Self.ambientRepeat })
                .min(by: { (ambientSaid[$0] ?? -.infinity) < (ambientSaid[$1] ?? -.infinity) }) else { return nil }
        ambientSaid[line] = now
        lastSaid = now
        return line
    }
}
