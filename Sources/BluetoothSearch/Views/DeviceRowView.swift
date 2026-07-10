import SwiftUI

// MARK: - RSSI Signal Bars

struct SignalBarsView: View {
    let strength: Int  // 0–4
    let color: Color
    let size: CGFloat

    init(strength: Int, color: Color, size: CGFloat = 14) {
        self.strength = strength
        self.color    = color
        self.size     = size
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: size * 0.18) {
            ForEach(0..<4, id: \.self) { index in
                let active = index < strength
                RoundedRectangle(cornerRadius: 2)
                    .fill(active ? color : Color.white.opacity(0.12))
                    .frame(
                        width:  size * 0.22,
                        height: size * (0.35 + Double(index) * 0.22)
                    )
                    .animation(.easeOut(duration: 0.3).delay(Double(index) * 0.05), value: strength)
            }
        }
        .frame(width: size * 0.22 * 4 + size * 0.18 * 3, height: size, alignment: .bottom)
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 4) {
            if status == .connecting {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                    .tint(status.color)
            } else {
                Circle()
                    .fill(status.color)
                    .frame(width: 6, height: 6)
            }
            Text(status.shortLabel)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(status.color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(status.color.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Device Row View

struct DeviceRowView: View {
    @ObservedObject var device: BLEDevice
    @EnvironmentObject var nicknameStore: NicknameStore
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Signal & icon
                ZStack {
                    Circle()
                        .fill(device.rssiColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: deviceIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [device.rssiColor, device.rssiColor.opacity(0.7)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                }

                // Info
                let nickname = nicknameStore.nickname(for: device.peripheralUUID)
                VStack(alignment: .leading, spacing: 3) {
                    // 별명이 있으면 별명을 주 이름으로
                    HStack(spacing: 4) {
                        Text(nickname ?? device.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)

                        if nickname != nil {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.appDiscovered)
                        }
                    }

                    // 별명이 있으면 원래 이름을, 없으면 UUID를 서브텍스트로
                    if let nick = nickname {
                        Text(device.name)
                            .font(.system(size: 10))
                            .foregroundColor(.textTertiary)
                            .lineLimit(1)
                        let _ = nick  // suppress warning
                    } else {
                        Text(device.peripheralUUID.prefix(18) + "…")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.textTertiary)
                    }
                }

                Spacer()

                // Right side
                VStack(alignment: .trailing, spacing: 4) {
                    SignalBarsView(strength: device.rssiStrength, color: device.rssiColor, size: 14)
                    Text("\(device.rssi) dBm")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(device.rssiColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected
                          ? Color.appAccent.opacity(0.12)
                          : Color.appSurface2.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isSelected ? Color.appAccent.opacity(0.4) : Color.appBorder,
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if device.status.isConnected {
                StatusBadge(status: device.status)
                    .offset(x: 4, y: -6)
            }
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }

    private var deviceIcon: String {
        let name = device.name.lowercased()
        if name.contains("heart") || name.contains("hr")      { return "heart.fill" }
        if name.contains("band") || name.contains("watch")     { return "applewatch" }
        if name.contains("headphone") || name.contains("ear")  { return "headphones" }
        if name.contains("keyboard")                           { return "keyboard" }
        if name.contains("mouse")                              { return "computermouse" }
        if name.contains("sensor")                             { return "sensor.fill" }
        if name.contains("beacon")                             { return "dot.radiowaves.left.and.right" }
        return "antenna.radiowaves.left.and.right"
    }
}
