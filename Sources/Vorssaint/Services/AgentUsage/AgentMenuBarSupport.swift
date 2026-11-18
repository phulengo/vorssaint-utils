// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the menu bar's AI reading shows: one agent's session and weekly
/// allowance, each as a share or a dash while the agent has reported none.
struct AgentMenuBarReading: Equatable {
    let session: String
    let weekly: String
    /// What a bar or a ring fills with, nil while the window is unread.
    var sessionShare: AgentMenuBarShare? = nil
    var weeklyShare: AgentMenuBarShare? = nil

    static let unknown = AgentMenuBarReading(session: AgentMenuBarSupport.placeholder,
                                             weekly: AgentMenuBarSupport.placeholder)
}

/// One window as a gauge draws it: filled with the share the number shows,
/// left or used, and coloured by the share used.
struct AgentMenuBarShare: Equatable {
    let shown: Double
    let used: Double
}

/// The AI reading pinned to the menu bar. It reads nothing of its own: the
/// AI section of Dynamic Island already follows the agents' limits, and the
/// pinned reading only counts as one more place that shows them, which keeps
/// Claude's account checks going at their unhurried pace while the page is
/// closed.
enum AgentMenuBarSupport {
    /// The agents whose plans report a session and a weekly window.
    static let providers: [AgentProvider] = [.claude, .codex]
    static let placeholder = "–"

    static func provider(in defaults: UserDefaults = .standard) -> AgentProvider {
        provider(stored: defaults.string(forKey: DefaultsKey.menuBarAIAgentsProvider))
    }

    /// Claude Code unless the stored choice names another agent it can show.
    static func provider(stored: String?) -> AgentProvider {
        AgentProvider(rawValue: stored ?? "").flatMap { providers.contains($0) ? $0 : nil } ?? .claude
    }

    /// The reading is pinned and its feature installed, whether or not the
    /// AI section runs to fill it.
    static func isShown(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: DefaultsKey.menuBarAIAgents) && AppFeature.notchAgents.isAvailable(in: defaults)
    }

    /// The plan's own windows, as left or used the way the island's Limits
    /// card shows them. A window that renewed since it was read has nothing
    /// spent yet, and a model's own allowance is never the plan's.
    static func reading(_ limits: AgentLimits?, display: NotchAgentLimitDisplay, now: Date) -> AgentMenuBarReading {
        func share(_ kind: AgentLimitWindow.Kind) -> AgentMenuBarShare? {
            guard let window = planWindow(kind, in: limits) else { return nil }
            let current = AgentLimitSupport.current(window, at: now)
            return AgentMenuBarShare(shown: display == .used ? current.usedFraction : current.remainingFraction,
                                     used: current.usedFraction)
        }
        func text(_ share: AgentMenuBarShare?) -> String {
            share.map { "\(Int(($0.shown * 100).rounded()))%" } ?? placeholder
        }
        let session = share(.session)
        let weekly = share(.weekly)
        return AgentMenuBarReading(session: text(session), weekly: text(weekly),
                                   sessionShare: session, weeklyShare: weekly)
    }

    /// When a shown window next renews, so the bar can redraw then even if
    /// nothing else changes; nil while neither has a renewal ahead.
    static func nextRenewal(_ limits: AgentLimits?, after now: Date) -> Date? {
        [AgentLimitWindow.Kind.session, .weekly]
            .compactMap { planWindow($0, in: limits)?.resetsAt }
            .filter { $0 > now }
            .min()
    }

    private static func planWindow(_ kind: AgentLimitWindow.Kind, in limits: AgentLimits?) -> AgentLimitWindow? {
        limits?.windows.first { $0.kind == kind && $0.scope == nil }
    }
}
