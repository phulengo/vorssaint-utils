// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import ImageIO

// A companion made of photographed parts that turn at their joints, as a
// puppet does. Rocky is one: his carapace and each segment of his five legs
// are cut from a photo of a stone statue, with the pivots where they meet,
// so every pixel of him is real stone. The rig is data in the app's
// resources; this file reads it, poses it and places it in the companion's
// square, inside the geodesic ball when he has one.

struct NotchMascotPuppet: Equatable {
    struct Part: Equatable {
        let id: String
        let file: String
        /// Where the part's picture sits in the rig's frame, and its size.
        let offset: CGPoint
        let size: CGSize
        /// The joint it turns about, in the rig's frame; nil for none.
        let pivot: CGPoint?
        let parent: String?
        /// Back to front.
        let z: Int
        /// The outline of its stone, as a few points in the rig's frame.
        let hull: [CGPoint]
    }

    /// The rig's frame, in source pixels.
    let width: CGFloat
    let height: CGFloat
    /// Back to front.
    let parts: [Part]
    /// Where each standing fist meets the ground.
    let feet: [String: CGPoint]

    var groundY: CGFloat { feet.values.map(\.y).max() ?? height }
    func part(_ id: String) -> Part? { parts.first { $0.id == id } }
    /// The one part with no parent: the carapace.
    var root: Part? { parts.first { $0.parent == nil } }

    // MARK: Loading

    /// Rocky, as the app ships him; nil if his resources are missing.
    static let rocky: NotchMascotPuppet? = Bundle.main.resourceURL.flatMap { load(from: $0.appending(path: "Companion/Rocky")) }

    static func load(from directory: URL) -> NotchMascotPuppet? {
        guard let data = try? Data(contentsOf: directory.appending(path: "rig.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let width = json["width"] as? Double, let height = json["height"] as? Double,
              let rawParts = json["parts"] as? [[String: Any]] else { return nil }
        func point(_ value: Any?) -> CGPoint? {
            guard let pair = value as? [Double], pair.count == 2 else { return nil }
            return CGPoint(x: pair[0], y: pair[1])
        }
        var parts: [Part] = []
        for raw in rawParts {
            guard let id = raw["id"] as? String, let file = raw["file"] as? String,
                  let offset = point(raw["offset"]), let size = point(raw["size"]) else { return nil }
            // Only a plain file name in the rig's own folder.
            guard !file.contains("/"), !file.hasPrefix(".") else { return nil }
            parts.append(Part(id: id, file: file, offset: offset, size: CGSize(width: size.x, height: size.y),
                              pivot: point(raw["pivot"]), parent: raw["parent"] as? String, z: raw["z"] as? Int ?? 0,
                              hull: (raw["hull"] as? [[Double]] ?? []).compactMap { point($0) }))
        }
        let feet = (json["feet"] as? [String: [Double]] ?? [:]).compactMapValues { point($0) }
        return NotchMascotPuppet(width: width, height: height, parts: parts.sorted { $0.z < $1.z }, feet: feet)
    }

    /// Each part's picture, by part id, from the rig's folder.
    static func images(of puppet: NotchMascotPuppet, in directory: URL) -> [String: CGImage] {
        var images: [String: CGImage] = [:]
        for part in puppet.parts {
            guard let source = CGImageSourceCreateWithURL(directory.appending(path: part.file) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            images[part.id] = image
        }
        return images
    }

    // MARK: Posing

    /// Each part's place for `pose`, in the rig's frame: the carapace moves
    /// and leans about its pivot, and every other part turns about its own
    /// joint and follows its parent.
    func transforms(_ pose: NotchMascotPuppetPose) -> [String: CGAffineTransform] {
        var done: [String: CGAffineTransform] = [:]
        func about(_ pivot: CGPoint?, _ degrees: CGFloat) -> CGAffineTransform {
            guard let pivot, degrees != 0 else { return .identity }
            return CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
                .concatenating(CGAffineTransform(rotationAngle: degrees * .pi / 180))
                .concatenating(CGAffineTransform(translationX: pivot.x, y: pivot.y))
        }
        func place(_ part: Part, depth: Int = 0) -> CGAffineTransform {
            if let known = done[part.id] { return known }
            let own = about(part.pivot, pose.turns[part.id] ?? 0)
            let result: CGAffineTransform
            if let parentID = part.parent, let parent = self.part(parentID), depth < parts.count {
                result = own.concatenating(place(parent, depth: depth + 1))
            } else {
                result = about(part.pivot, pose.rot).concatenating(own).concatenating(CGAffineTransform(translationX: pose.dx, y: pose.dy))
            }
            done[part.id] = result
            return result
        }
        for part in parts { _ = place(part) }
        return done
    }

    // MARK: Placing

    struct Placement: Equatable {
        /// How many points one source pixel spans.
        let scale: CGFloat
        /// Where the rig's frame begins in the square.
        let origin: CGPoint
        /// What the companion takes up in the square.
        let figure: CGRect
    }

    /// The ball, in shares of the square: its middle and its radius.
    static let ballRadius: CGFloat = 0.47

    /// Rocky in a square of `size` points: standing on its floor, as wide as
    /// it allows, or inside his ball, as big as fits with every move he makes there.
    func placement(size: CGFloat, enclosed: Bool) -> Placement {
        if enclosed {
            let fit = ballFit, radius = size * Self.ballRadius, scale = fit.width * radius / width
            let origin = CGPoint(x: size / 2 - width / 2 * scale + fit.across * radius,
                                 y: size / 2 - fit.feet * radius - groundY * scale)
            let ball = (1 - 2 * Self.ballRadius) / 2 * size
            return Placement(scale: scale, origin: origin, figure: CGRect(x: ball, y: ball, width: size - 2 * ball, height: size - 2 * ball))
        }
        let scale = size * 0.96 / width
        let origin = CGPoint(x: (size - width * scale) / 2, y: size * 0.97 - groundY * scale)
        let top = parts.map(\.offset.y).min() ?? 0
        return Placement(scale: scale, origin: origin,
                         figure: CGRect(x: origin.x, y: origin.y + top * scale, width: width * scale, height: (groundY - top) * scale))
    }

    /// In his ball he keeps his gestures smaller, so his arms never reach the glass.
    static let ballDamping: CGFloat = 0.6
    /// How far from the ball's middle any of him may reach, as a share of its radius.
    static let ballRoom: CGFloat = 0.86

    struct BallFit: Equatable {
        /// His width as a share of the ball's radius.
        let width: CGFloat
        /// His feet's height from the ball's middle, as a share of its radius; negative is below.
        let feet: CGFloat
        /// How far across he is moved to balance a one-sided reach.
        let across: CGFloat
    }

    /// The largest Rocky that fits in the ball whatever he does in there,
    /// standing as low as he can.
    var ballFit: BallFit { NotchMascotPuppetFitCache.shared.fit(for: self) }

    func computeBallFit() -> BallFit {
        let points = reach(damping: Self.ballDamping)
        let room = Self.ballRoom
        var width: CGFloat = 1.6
        while width >= 0.3 {
            let k = width / self.width
            var across: CGFloat = 0
            while abs(across) <= 0.3 {
                var low = -CGFloat.infinity, high = CGFloat.infinity, fits = true
                for point in points {
                    let x = (point.x - self.width / 2) * k + across, y = (groundY - point.y) * k
                    let left = room * room - x * x
                    if left < 0 { fits = false; break }
                    let r = left.squareRoot()
                    low = max(low, -r - y); high = min(high, r - y)
                    if low > high { fits = false; break }
                }
                if fits { return BallFit(width: width, feet: low, across: across) }
                across = across > 0 ? -across : 0.025 - across
            }
            width -= 0.01
        }
        return BallFit(width: 0.3, feet: -0.2, across: 0)
    }

    /// The farthest his stone reaches in each direction, over every move he
    /// plays, with his gestures scaled by `damping`.
    func reach(damping: CGFloat = 1) -> [CGPoint] {
        let middle = CGPoint(x: width / 2, y: groundY - height * 0.45)
        var farthest: [Int: (point: CGPoint, distance: CGFloat)] = [:]
        let tracks = NotchMascotReaction.allCases.map { NotchMascotPuppetMotion.track(for: $0) }
            + NotchMascotMood.allCases.map { NotchMascotPuppetMotion.track(for: $0) } + [NotchMascotPuppetMotion.stroll]
            + (NotchMascotPuppetMotion.acts(for: .show) + NotchMascotPuppetMotion.acts(for: .waiting)).map(\.track)
        for track in tracks {
            for step in 0...24 {
                let pose = track.pose(at: Double(step) / 24).damped(damping)
                let placed = transforms(pose)
                for part in parts {
                    guard let transform = placed[part.id] else { continue }
                    for point in part.hull {
                        let p = point.applying(transform), dx = p.x - middle.x, dy = p.y - middle.y
                        let bin = Int((atan2(dy, dx) / (2 * .pi) * 96).rounded()), distance = (dx * dx + dy * dy).squareRoot()
                        if (farthest[bin]?.distance ?? -1) < distance { farthest[bin] = (p, distance) }
                    }
                }
            }
        }
        return farthest.values.map(\.point)
    }
}

/// Fits computed once per rig, since the search samples every move he plays.
final class NotchMascotPuppetFitCache: @unchecked Sendable {
    static let shared = NotchMascotPuppetFitCache()
    private let lock = NSLock()
    private var fits: [String: NotchMascotPuppet.BallFit] = [:]

    func fit(for puppet: NotchMascotPuppet) -> NotchMascotPuppet.BallFit {
        let key = "\(puppet.width)x\(puppet.height)|\(puppet.parts.map(\.id).joined(separator: ","))"
        lock.lock(); defer { lock.unlock() }
        if let known = fits[key] { return known }
        let fit = puppet.computeBallFit()
        fits[key] = fit
        return fit
    }
}

// MARK: - Poses and moves

/// What Rocky plays while the closed island has nothing else to show: his
/// little acts, waiting acts while the music is paused, or nothing.
enum NotchMascotPerformance: Equatable {
    case off, show, waiting

    /// How long he rests between one act and the next.
    static let spacing: ClosedRange<TimeInterval> = 20...40
}

/// One of his acts, the line he may say with it now and then in the
/// island, and the one he says playing it on a show out of the island.
struct NotchMascotPuppetAct: Equatable {
    let track: NotchMascotPuppetTrack
    var line: NotchMascotLine?
    var showLine: NotchMascotLine?

    init(_ track: NotchMascotPuppetTrack, line: NotchMascotLine? = nil, show: NotchMascotLine? = nil) {
        self.track = track
        self.line = line
        self.showLine = show
    }
}

/// A beat of a show out of the island: an act, and what he says with it.
struct NotchMascotShowBeat: Equatable {
    let act: NotchMascotPuppetAct
    let line: NotchMascotLine
}

/// The carapace's offset and lean, in source pixels and degrees clockwise,
/// and each joint's turn in degrees clockwise on screen.
struct NotchMascotPuppetPose: Equatable {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var rot: CGFloat = 0
    var turns: [String: CGFloat] = [:]

    static let rest = NotchMascotPuppetPose()

    /// The same pose with the front legs' gestures and any rise scaled by `share`.
    func damped(_ share: CGFloat) -> NotchMascotPuppetPose {
        guard share < 1 else { return self }
        var pose = self
        for id in ["FLU", "FLL", "FRU", "FRL"] { if let turn = pose.turns[id] { pose.turns[id] = turn * share } }
        pose.dx *= share
        if pose.dy < 0 { pose.dy *= share }
        return pose
    }

    func scaled(_ share: CGFloat) -> NotchMascotPuppetPose {
        NotchMascotPuppetPose(dx: dx * share, dy: dy * share, rot: rot * share, turns: turns.mapValues { $0 * share })
    }

    func adding(_ other: NotchMascotPuppetPose) -> NotchMascotPuppetPose {
        var turns = self.turns
        for (id, turn) in other.turns { turns[id, default: 0] += turn }
        return NotchMascotPuppetPose(dx: dx + other.dx, dy: dy + other.dy, rot: rot + other.rot, turns: turns)
    }

    /// Every joint this pose or `other` turns.
    func joints(with other: NotchMascotPuppetPose) -> Set<String> { Set(turns.keys).union(other.turns.keys) }
}

/// A move as keyframes over its length, from 0 to 1, eased between them.
struct NotchMascotPuppetTrack: Equatable {
    struct Key: Equatable {
        let at: Double
        let pose: NotchMascotPuppetPose
    }

    /// How long it plays, in seconds, and whether it repeats.
    let duration: TimeInterval
    let loops: Bool
    let keys: [Key]

    func pose(at share: Double) -> NotchMascotPuppetPose {
        guard let first = keys.first, let last = keys.last else { return .rest }
        if share <= first.at { return first.pose }
        if share >= last.at { return last.pose }
        let next = keys.firstIndex { $0.at >= share } ?? keys.count - 1
        let a = keys[max(0, next - 1)], b = keys[next]
        let t = (share - a.at) / max(1e-6, b.at - a.at), eased = CGFloat(t * t * (3 - 2 * t))
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * eased }
        var turns: [String: CGFloat] = [:]
        for id in a.pose.joints(with: b.pose) { turns[id] = mix(a.pose.turns[id] ?? 0, b.pose.turns[id] ?? 0) }
        return NotchMascotPuppetPose(dx: mix(a.pose.dx, b.pose.dx), dy: mix(a.pose.dy, b.pose.dy), rot: mix(a.pose.rot, b.pose.rot), turns: turns)
    }

    /// Every joint the move turns.
    var joints: Set<String> { keys.reduce(into: Set<String>()) { $0.formUnion($1.pose.turns.keys) } }
}

/// Rocky's moves: what each reaction and mood looks like on a five-legged,
/// eyeless stone body. He has no face, so his feelings are in his carapace
/// and his legs: a fist bump, a two-handed thump, a slump, a lifted leg to
/// listen, a wave, taps on the ground.
enum NotchMascotPuppetMotion {
    private typealias P = NotchMascotPuppetPose
    private static func pose(dx: CGFloat = 0, dy: CGFloat = 0, rot: CGFloat = 0, _ turns: [String: CGFloat] = [:]) -> P {
        P(dx: dx, dy: dy, rot: rot, turns: turns)
    }
    private static func track(_ duration: TimeInterval, loops: Bool = false, _ keys: [(Double, P)]) -> NotchMascotPuppetTrack {
        NotchMascotPuppetTrack(duration: duration, loops: loops, keys: keys.map { .init(at: $0.0, pose: $0.1) })
    }
    /// Short taps of the front-right fist on the ground at each of `times`.
    private static func taps(_ times: [Double], width: Double = 0.08) -> [(Double, P)] {
        var keys: [(Double, P)] = [(0, .rest)]
        for at in times { keys += [(at - width, .rest), (at, pose(["FRU": -4, "FRL": -16])), (at + width, .rest)] }
        return keys + [(1, .rest)]
    }

    /// Slumped: the carapace sinks and leans, the front legs splay.
    static let slump: NotchMascotPuppetPose = pose(dy: 16, rot: 3, ["FLU": 10, "FLL": -12, "FRU": -10, "FRL": 12, "BLL": 6, "BRL": -6])

    static let idle: NotchMascotPuppetTrack = track(3.2, loops: true, [(0, .rest), (0.5, pose(dy: -3, ["FLU": 1.5, "FRU": -1.5])), (1, .rest)])

    /// Walking: the front legs step in turn while the body shifts its weight.
    static let stroll: NotchMascotPuppetTrack = track(1.6, loops: true, [
        (0, .rest), (0.25, pose(dx: -3, rot: -1.5, ["FRU": -5, "FRL": -14, "BLL": 6])), (0.5, .rest),
        (0.75, pose(dx: 3, rot: 1.5, ["FLU": 5, "FLL": 14, "BRL": -6])), (1, .rest),
    ])

    static func track(for reaction: NotchMascotReaction) -> NotchMascotPuppetTrack {
        let length = reaction.length
        switch reaction {
        case .celebrate:   // "Fist my bump."
            let bump = pose(dx: 4, ["FRU": -22, "FRL": -70])
            return track(length, [(0, .rest), (0.15, pose(rot: -2, ["FRU": -14, "FRL": -35])), (0.3, bump),
                                  (0.4, pose(dx: 5, ["FRU": -22, "FRL": -58])), (0.5, bump), (0.85, bump), (1, .rest)])
        case .love:        // a contented wiggle
            let left = pose(dx: -3, dy: 3, rot: -1.5), right = pose(dx: 3, dy: 3, rot: 1.5)
            return track(length, [(0, .rest), (0.12, right), (0.27, left), (0.42, right), (0.57, left), (0.72, right), (0.86, pose(dy: 3)), (1, .rest)])
        case .surprised:   // legs splay as he jolts, then two raps of a fist
            return track(length, [(0, .rest), (0.15, pose(["FLU": -6, "FLL": -10, "FRU": 6, "FRL": 10])), (0.32, .rest),
                                  (0.45, pose(["FRU": -5, "FRL": -18])), (0.55, .rest), (0.65, pose(["FRU": -5, "FRL": -18])), (0.75, .rest), (1, .rest)])
        case .flash:       // a flinch, then a lean to listen
            let listen = pose(rot: 4, ["FLU": 10, "FLL": 30])
            return track(length, [(0, .rest), (0.12, pose(dx: -3, rot: -2)), (0.3, .rest), (0.5, listen), (0.85, listen), (1, .rest)])
        case .confused:    // a slump and a slow shake
            let tilt = { (r: CGFloat) in NotchMascotPuppetPose(dx: slump.dx, dy: slump.dy, rot: slump.rot + r, turns: slump.turns) }
            return track(length, [(0, .rest), (0.25, slump), (0.4, tilt(2)), (0.55, tilt(-2)), (0.7, tilt(2)), (0.85, slump), (1, .rest)])
        case .wakeUp:      // up from a crouch, and a wave
            let crouch = slump.scaled(0.75)
            return track(length, [(0, crouch), (0.25, .rest), (0.35, pose(["FRU": -24, "FRL": -57])), (0.47, pose(["FRU": -24, "FRL": -70])),
                                  (0.59, pose(["FRU": -24, "FRL": -45])), (0.71, pose(["FRU": -24, "FRL": -70])), (0.83, pose(["FRU": -24, "FRL": -45])),
                                  (0.92, pose(["FRU": -24, "FRL": -57])), (1, .rest)])
        case .yawn:        // a nod, then drowsy
            let drowsy = slump.scaled(0.5).adding(pose(rot: 2.5))
            return track(length, [(0, .rest), (0.15, pose(dy: 3, rot: 5)), (0.3, .rest), (0.6, drowsy), (0.88, drowsy), (1, .rest)])
        case .perk:        // a leg lifted, listening
            let listen = pose(rot: 4, ["FLU": 15, "FLL": 55])
            return track(length, [(0, .rest), (0.2, listen), (0.9, listen), (1, .rest)])
        case .bounce:      // two raps, then a point: time to go
            let point = pose(dx: 3, rot: -2, ["FRU": -24, "FRL": -52])
            return track(length, [(0, .rest), (0.07, pose(["FRU": -5, "FRL": -18])), (0.14, .rest), (0.22, pose(["FRU": -5, "FRL": -18])),
                                  (0.29, .rest), (0.42, point), (0.9, point), (1, .rest)])
        case .hush:        // he settles and goes quiet
            let hush = pose(dy: 6, rot: -2, ["FLU": 6, "FLL": -18])
            return track(length, [(0, .rest), (0.25, hush), (0.85, hush), (1, .rest)])
        case .ready:       // three taps: counting
            return track(length, taps([0.2, 0.45, 0.7]))
        case .groove:      // swaying to the music
            let left = pose(dx: -6, rot: -3, ["FLL": 3, "FRL": 3]), right = pose(dx: 6, rot: 3, ["FLL": -3, "FRL": -3])
            return track(length, [(0, .rest), (0.12, left), (0.37, right), (0.62, left), (0.87, right), (1, .rest)])
        }
    }

    /// What he plays, one now and then, while the island has nothing else
    /// to show: little turns of his own, or, with the music paused, waiting
    /// for it to come back. Each ends at rest, where his breathing goes on.
    static func acts(for performance: NotchMascotPerformance) -> [NotchMascotPuppetAct] {
        switch performance {
        case .off:
            return []
        case .show:
            let raised = pose(["FLU": 15, "FLL": 55]), strike = pose(dy: 2, ["FLU": 2, "FLL": 8])
            let splay = pose(dy: -8, ["FLU": 12, "FLL": -16, "FRU": -12, "FRL": 16])
            let left = pose(dx: -6, rot: -3, ["FLU": 8, "FLL": 20]), right = pose(dx: 6, rot: 3, ["FRU": -8, "FRL": -20])
            let wave = { (elbow: CGFloat) in pose(["FRU": -24, "FRL": elbow]) }
            return [
                // A rhythm tapped out on the ground.
                .init(track(3.2, taps([0.15, 0.3, 0.45, 0.65, 0.8], width: 0.05)), show: .showTap),
                // Up on his legs, splayed wide: a stretch.
                .init(track(3.6, [(0, .rest), (0.3, splay), (0.65, splay), (1, .rest)]), show: .showStretch),
                // A lean one way and the other, looking around.
                .init(track(4, [(0, .rest), (0.2, pose(dx: -3, rot: -4)), (0.4, pose(dx: -3, rot: -4)),
                                (0.6, pose(dx: 3, rot: 4)), (0.8, pose(dx: 3, rot: 4)), (1, .rest)]), show: .showLook),
                // Hammering something together: "I make thing."
                .init(track(3.6, [(0, .rest), (0.12, raised), (0.22, strike), (0.34, raised), (0.44, strike),
                                  (0.56, raised), (0.66, strike), (0.85, strike), (1, .rest)]), line: .make, show: .showHammer),
                // A little dance, a leg up on each side.
                .init(track(4, [(0, .rest), (0.15, left), (0.35, right), (0.55, left), (0.75, right), (1, .rest)]),
                      show: .showDance),
                // A wave.
                .init(track(2.8, [(0, .rest), (0.15, wave(-57)), (0.3, wave(-70)), (0.45, wave(-45)), (0.6, wave(-70)),
                                  (0.75, wave(-45)), (0.9, wave(-57)), (1, .rest)])),
            ]
        case .waiting:
            let sit = slump.scaled(0.5), tap = sit.adding(pose(["FRU": -3, "FRL": -12]))
            let sunk = pose(dy: 6, ["FLL": -6, "FRL": 6])
            return [
                // Sat down, tapping a foot.
                .init(track(4, [(0, .rest), (0.2, sit), (0.35, tap), (0.42, sit), (0.55, tap), (0.62, sit),
                                (0.75, tap), (0.82, sit), (1, .rest)])),
                // A long look over, as if the music might be back.
                .init(track(3.6, [(0, .rest), (0.25, pose(dx: 3, rot: 4)), (0.6, pose(dx: 3, rot: 4)),
                                  (0.75, pose(dx: -1, rot: -1.5)), (1, .rest)])),
                // A slow sigh.
                .init(track(3.2, [(0, .rest), (0.45, sunk), (0.6, sunk), (1, .rest)])),
            ]
        }
    }

    /// A bow to end a show: the carapace dips, the front legs spread.
    static let bow: NotchMascotPuppetTrack = track(2.8, [
        (0, .rest), (0.25, pose(dy: 6, rot: -6, ["FLU": 8, "FLL": -10, "FRU": -8, "FRL": 10])),
        (0.6, pose(dy: 6, rot: -6, ["FLU": 8, "FLL": -10, "FRU": -8, "FRL": 10])), (1, .rest),
    ])

    /// A show out of the island: a wave hello, one of his other acts, a
    /// different one each `round`, and a bow goodbye, each with its line.
    static func showtime(round: Int) -> [NotchMascotShowBeat] {
        let acts = Self.acts(for: .show)
        guard let wave = acts.last else { return [] }
        let others = acts.dropLast().filter { $0.showLine != nil }
        var beats = [NotchMascotShowBeat(act: wave, line: .showHello)]
        if !others.isEmpty {
            let act = others[((round % others.count) + others.count) % others.count]
            beats.append(NotchMascotShowBeat(act: act, line: act.showLine ?? .showHello))
        }
        beats.append(NotchMascotShowBeat(act: NotchMascotPuppetAct(bow), line: .showBye))
        return beats
    }

    /// Below this size, in points, his breathing moves him a fraction of a
    /// point on screen: at rest or dozing he holds the pose still there, so
    /// the screen is not redrawn all day for motion nobody can see.
    static let breathingSize: CGFloat = 60

    /// Whether `mood`'s pose is held still at `size`; the moods he shows with
    /// his legs, searching and thinking, keep moving at any size.
    static func holdsStill(_ mood: NotchMascotMood, size: CGFloat) -> Bool {
        switch mood {
        case .searching, .thinking: return false
        default: return size < breathingSize
        }
    }

    /// The pose a mood holds, breathing; neutral for the moods he shows with his eyes elsewhere.
    static func track(for mood: NotchMascotMood) -> NotchMascotPuppetTrack {
        switch mood {
        case .sleepy:
            let deep = slump.scaled(0.7).adding(pose(dy: -1.2, rot: 1.9))
            return track(4, loops: true, [(0, deep), (0.5, deep.adding(pose(dy: 3))), (1, deep)])
        case .searching:
            return track(2.4, loops: true, [
                (0, .rest), (0.12, pose(rot: -2, ["FLU": 4, "FLL": 14])), (0.25, pose(rot: -2)), (0.37, pose(rot: 2, ["FRU": -4, "FRL": -14])),
                (0.5, pose(rot: 2)), (0.62, pose(rot: -2, ["FLU": 4, "FLL": 14])), (0.75, pose(rot: -2)), (0.87, pose(rot: 2, ["FRU": -4, "FRL": -14])), (1, .rest),
            ])
        case .thinking:
            let think = pose(rot: -3, ["FRU": -20, "FRL": -40])
            return track(2.8, loops: true, [(0, think), (0.25, think.adding(pose(["FRL": 5]))), (0.5, think), (0.75, think.adding(pose(["FRL": 5]))), (1, think)])
        default:
            return idle
        }
    }
}

// MARK: - The ball

extension NotchMascotGeometry {
    /// Rocky's ball, flattened for the island: the film's icosahedron with a
    /// vertex up, tipped so a five-spoke star sits off-centre toward the
    /// viewer. Struts behind him, three lit panels, struts in front, a bolder
    /// rim and one straight glint.
    struct GeodesicBall {
        let back: CGPath
        let panels: [CGPath]
        let front: CGPath
        let rim: CGPath
        let glint: CGPath
        let hubs: [CGPoint]
    }

    static func geodesicBall(size: CGFloat) -> GeodesicBall {
        let radius = size * NotchMascotPuppet.ballRadius, middle = CGPoint(x: size / 2, y: size / 2)
        let ring = { (y: CGFloat, r: CGFloat, offset: CGFloat) in (0..<5).map { k -> [CGFloat] in
            let a = offset + CGFloat(k) * 2 * .pi / 5
            return [r * cos(a), y, r * sin(a)]
        } }
        let tall = 1 / CGFloat(5).squareRoot(), wide = 2 / CGFloat(5).squareRoot()
        let vertices: [[CGFloat]] = [[0, 1, 0]] + ring(tall, wide, 0) + ring(-tall, wide, .pi / 5) + [[0, -1, 0]]
        var faces: [[Int]] = []
        for k in 0..<5 {
            let u = 1 + k, u2 = 1 + (k + 1) % 5, l = 6 + k, l2 = 6 + (k + 1) % 5
            faces += [[0, u, u2], [u, l, u2], [u2, l, l2], [11, l2, l]]
        }
        let turnX: CGFloat = -20 * .pi / 180, turnY: CGFloat = 18 * .pi / 180
        let turned = vertices.map { v -> [CGFloat] in
            let x = v[0] * cos(turnY) + v[2] * sin(turnY), z0 = -v[0] * sin(turnY) + v[2] * cos(turnY)
            return [x, v[1] * cos(turnX) - z0 * sin(turnX), v[1] * sin(turnX) + z0 * cos(turnX)]
        }
        let at = { (i: Int) in CGPoint(x: middle.x + turned[i][0] * radius, y: middle.y - turned[i][1] * radius) }
        var edges = Set<[Int]>()
        for f in faces { for (a, b) in [(f[0], f[1]), (f[1], f[2]), (f[2], f[0])] { edges.insert([min(a, b), max(a, b)]) } }
        let back = CGMutablePath(), front = CGMutablePath()
        for edge in edges.sorted(by: { $0.lexicographicallyPrecedes($1) }) {
            let path = turned[edge[0]][2] + turned[edge[1]][2] < 0 ? back : front
            path.move(to: at(edge[0])); path.addLine(to: at(edge[1]))
        }
        // The three front panels turned most toward the light, top left.
        let centroid = { (f: [Int]) in (0..<3).map { c in f.reduce(0) { $0 + turned[$1][c] } / 3 } }
        let lit = faces.filter { centroid($0)[2] > 0 }.sorted {
            let a = centroid($0), b = centroid($1)
            return a[1] * 0.6 - a[0] * 0.5 + a[2] * 0.6 > b[1] * 0.6 - b[0] * 0.5 + b[2] * 0.6
        }.prefix(3)
        let panels = lit.map { f -> CGPath in let p = CGMutablePath(); p.addLines(between: f.map(at)); p.closeSubpath(); return p }
        let glint = CGMutablePath()
        if let brightest = lit.first {
            let a = turned[brightest[0]], b = turned[brightest[1]], c = turned[brightest[2]]
            let inset = { (v: [CGFloat]) in (0..<3).map { v[$0] + (c[$0] - v[$0]) * 0.12 } }
            let p0 = inset((0..<3).map { a[$0] + (b[$0] - a[$0]) * 0.15 }), p1 = inset((0..<3).map { a[$0] + (b[$0] - a[$0]) * 0.85 })
            glint.move(to: CGPoint(x: middle.x + p0[0] * radius, y: middle.y - p0[1] * radius))
            glint.addLine(to: CGPoint(x: middle.x + p1[0] * radius, y: middle.y - p1[1] * radius))
        }
        // The silhouette: the hull of every vertex.
        let corners: [CGPoint] = (0..<turned.count).map(at)
        let points = corners.sorted { (a: CGPoint, b: CGPoint) -> Bool in a.x == b.x ? a.y < b.y : a.x < b.x }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for p in points { while lower.count > 1, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }; lower.append(p) }
        for p in points.reversed() { while upper.count > 1, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }; upper.append(p) }
        let rim = CGMutablePath(); rim.addLines(between: Array(lower.dropLast() + upper.dropLast())); rim.closeSubpath()
        let hubs = (0..<turned.count).filter { turned[$0][2] >= 0 }.map(at)
        return GeodesicBall(back: back, panels: Array(panels), front: front, rim: rim, glint: glint, hubs: hubs)
    }
}
