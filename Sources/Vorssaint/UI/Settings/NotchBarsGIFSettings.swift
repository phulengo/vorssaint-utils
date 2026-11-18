// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The GIFs added for the music bars, to choose again or delete, after the
/// bars themselves. Only the chosen GIF and the one under the pointer move.
struct NotchBarsGIFCollection: View {
    @ObservedObject var store: NotchBarsGIF
    let strings: NotchMusicExtrasStrings
    @State private var hovered: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let side: CGFloat = 44

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.side), spacing: 8, alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            tile(nil, label: strings.removeGIF) {
                Image(systemName: "waveform").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            }
            ForEach(store.items) { item in
                tile(item.id, label: strings.barsGIF) {
                    NotchBarsGIFView(data: item.data,
                                     animates: !reduceMotion && (store.selection == item.id || hovered == item.id))
                        .padding(6)
                }
                .overlay(alignment: .topTrailing) {
                    Button { store.delete(item.id) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color(nsColor: .systemGray))
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 5, y: -5)
                    .help(strings.deleteGIF)
                    .accessibilityLabel(strings.deleteGIF)
                }
                .onHover { inside in
                    if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
                }
            }
        }
    }

    private func tile<Content: View>(_ id: String?, label: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        let chosen = store.selection == id
        return Button { store.select(id) } label: {
            content()
                .frame(width: Self.side, height: Self.side)
                .background(.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(chosen ? Color.accentColor : .white.opacity(0.12), lineWidth: chosen ? 2 : 0.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// The closed music strip's own fit: the GIF's size and the room around what
/// the strip shows. The GIF can be as tall as the strip; the strip widens to
/// fit it.
struct NotchMusicStripFitSliders: View {
    let strings: NotchMusicExtrasStrings
    let showsGIFSize: Bool
    /// The strip's height on the island's display, the tallest a GIF can be.
    let stripHeight: CGFloat
    @AppStorage(DefaultsKey.notchMusicGIFSize) private var gifSize = NotchMusicStripFit.defaultGIFSide
    @AppStorage(DefaultsKey.notchMusicSidePadding) private var sidePadding = 0.0
    @AppStorage(DefaultsKey.notchMusicVerticalPadding) private var verticalPadding = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                if showsGIFSize {
                    let range = NotchMusicStripFit.gifSideRange
                    row(strings.gifSize, value: $gifSize,
                        range: range.lowerBound...max(range.lowerBound + 1, min(range.upperBound, Double(stripHeight))))
                }
                row(strings.sidePadding, value: $sidePadding, range: NotchMusicStripFit.paddingRange)
                row(strings.verticalPadding, value: $verticalPadding, range: NotchMusicStripFit.paddingRange)
            }
            Text(strings.stripFitHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let bounded = Binding(get: { min(range.upperBound, max(range.lowerBound, value.wrappedValue)) },
                              set: { value.wrappedValue = $0 })
        return GridRow {
            // The slider carries the name for VoiceOver.
            Text(title).fixedSize().accessibilityHidden(true)
            Slider(value: bounded, in: range, step: 1) { Text(title) }.labelsHidden()
            Text(Int(bounded.wrappedValue), format: .number)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}
