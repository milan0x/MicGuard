//
//  DevicePriorityListView.swift
//  MicGuard
//
//  Inline reorderable device list. The whole row is the click target for "use this device";
//  inner controls (arrows, remove, re-apply) are their own buttons so they don't trigger row select.
//

import SwiftUI

struct DevicePriorityListView: View {

    let devices: [DeviceEntry]
    let onUse: (Int) -> Void
    let onMoveUp: (Int) -> Void
    let onMoveDown: (Int) -> Void
    let onRemove: (Int) -> Void
    let onReapply: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if devices.isEmpty {
                Text("No devices found")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                HStack(spacing: 4) {
                    Text("Devices auto-select by priority order")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: onReapply) {
                        Label("Re-apply", systemImage: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Switch to the top connected device in your priority order")
                }
                .padding(.bottom, 2)

                // Cap the visible list at ~6 rows. Beyond that, the inner ScrollView
                // engages — keeps popover height predictable when device count is high.
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(devices.enumerated()), id: \.element.id) { index, entry in
                            DeviceRow(
                                entry: entry,
                                isFirst: index == 0,
                                isLast: index == devices.count - 1,
                                onUse: { onUse(index) },
                                onMoveUp: { onMoveUp(index) },
                                onMoveDown: { onMoveDown(index) },
                                onRemove: { onRemove(index) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }
}

private struct DeviceRow: View {

    let entry: DeviceEntry
    let isFirst: Bool
    let isLast: Bool
    let onUse: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    @State private var isHovered: Bool = false
    @State private var showUnsettableInfo: Bool = false

    /// Whether the row is interactive at all. Always true now — disconnected rows
    /// promote priority on click; connected non-active rows also switch the default.
    private var isClickable: Bool {
        !entry.isActive
    }

    private var hoverHighlight: Bool {
        isClickable
    }

    private var clickTooltip: String {
        if entry.isActive { return "" }
        if entry.isConnected { return "Click to use this device" }
        return "Click to move this device to the top — it'll activate when reconnected"
    }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onUse) {
                HStack(spacing: 6) {
                    ZStack {
                        if entry.isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(.secondary.opacity(entry.isConnected ? 0.6 : 0.4))
                        }
                    }
                    .font(.system(size: 12))
                    .frame(width: 16)

                    Text("#\(entry.priority)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 22, alignment: .leading)

                    Text(entry.displayName)
                        .font(.system(size: 12))
                        .foregroundColor(rowColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if entry.unsettable {
                        UnsettableInfoIcon(isShowing: $showUnsettableInfo)
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering && hoverHighlight
            }
            .help(clickTooltip)

            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(isFirst)
            .help("Move up")

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(isLast)
            .help("Move down")

            if !entry.isConnected {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(rowBackground)
        )
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }

    private var rowColor: Color {
        if entry.isActive { return .accentColor }
        if !entry.isConnected { return .secondary.opacity(0.55) }
        return .primary
    }

    private var rowBackground: Color {
        if entry.isActive { return Color.accentColor.opacity(0.08) }
        if isHovered { return Color.primary.opacity(0.06) }
        return .clear
    }
}

private struct UnsettableInfoIcon: View {
    @Binding var isShowing: Bool

    var body: some View {
        Button(action: { isShowing.toggle() }) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.blue)
        }
        .buttonStyle(.plain)
        .help("macOS won't accept this as a default device. Click for details.")
        .popover(isPresented: $isShowing, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("Can't be set as default")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text("macOS won't accept this as your system default — it's a virtual or loopback driver (Microsoft Teams Audio, BlackHole, aggregate devices, etc.).")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You can keep it in your priority list as a reference, but clicking won't switch to it.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 280)
        }
    }
}
