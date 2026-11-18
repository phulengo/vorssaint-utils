// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The AI tab: the AI page of Dynamic Island, with the same cards in the same
/// order, on a dark surface of its own like the island it comes from, so its
/// light type reads in a light panel too. The AI section is what reads the
/// agents, so while it is off the tab says so and leads to its settings
/// instead of showing an empty page.
struct AgentsSection: View {
    var collapsible = true
    /// The width the panel gives its sections.
    var width: CGFloat = 308
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchEnabled) private var notchEnabled = false
    @AppStorage(DefaultsKey.notchAgentsEnabled) private var agentsEnabled = false
    @AppStorage(DefaultsKey.notchHiddenModules) private var hiddenModules = ""

    private static let inset: CGFloat = 10

    var body: some View {
        let text = FeatureStrings.notchAgents(l10n.language)
        PanelSection(.agents, title: text.title, collapsible: collapsible) {
            if sectionRuns {
                NotchAgentsView(size: CGSize(width: width - Self.inset * 2, height: 0), inPanel: true)
                    .padding(Self.inset)
                    .frame(width: width, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black))
                    .environment(\.colorScheme, .dark)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text.panelOff)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(l10n.s.menuSettings) {
                        SettingsRouter.shared.request(AppFeature.notchAgents.settingsDestination)
                        appDelegate()?.openSettingsWindow()
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelCard()
            }
        }
    }

    /// Read again whenever the island, the section or its place among the
    /// island's sections changes.
    private var sectionRuns: Bool {
        _ = (notchEnabled, agentsEnabled, hiddenModules)
        return NotchAgentSupport.isEnabled()
    }
}
