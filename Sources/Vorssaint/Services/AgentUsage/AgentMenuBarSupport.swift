// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// What the menu bar's AI reading shows: one agent's session and weekly
/// allowance, each as a share or a dash while the agent has reported none.
struct AgentMenuBarReading: Equatable {
    let session: String
    let weekly: String

    static let unknown = AgentMenuBarReading(session: AgentMenuBarSupport.placeholder,
                                             weekly: AgentMenuBarSupport.placeholder)
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
        func share(_ kind: AgentLimitWindow.Kind) -> String {
            guard let window = planWindow(kind, in: limits) else { return placeholder }
            let current = AgentLimitSupport.current(window, at: now)
            let fraction = display == .used ? current.usedFraction : current.remainingFraction
            return "\(Int((fraction * 100).rounded()))%"
        }
        return AgentMenuBarReading(session: share(.session), weekly: share(.weekly))
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
