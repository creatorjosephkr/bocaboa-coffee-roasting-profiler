import SwiftUI

// MARK: - Sort Order

enum DeviceSortOrder: String, CaseIterable {
    case discovery = "발견 순"
    case rssi      = "신호 강도"
    case name      = "이름 순"

    var icon: String {
        switch self {
        case .discovery: return "clock"
        case .rssi:      return "antenna.radiowaves.left.and.right"
        case .name:      return "textformat"
        }
    }
}

// MARK: - Device List View

struct DeviceListView: View {
    @ObservedObject var manager: BluetoothManager
    @State private var searchText: String = ""
    @State private var sortOrder: DeviceSortOrder = .discovery
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.0

    var filteredDevices: [BLEDevice] {
        // 1. connectable filter
        let base = manager.showOnlyConnectable
            ? manager.devices.filter { $0.isConnectable }
            : manager.devices

        // 2. search filter
        let searched: [BLEDevice]
        if searchText.isEmpty {
            searched = base
        } else {
            let query = searchText.lowercased()
            searched = base.filter {
                $0.name.lowercased().contains(query) ||
                $0.peripheralUUID.lowercased().contains(query) ||
                ($0.manufacturerDataHex.lowercased().contains(query) && query.count >= 3)
            }
        }

        // 3. sort
        switch sortOrder {
        case .discovery:
            return searched  // 발견 순 = 원래 순서 유지
        case .rssi:
            return searched.sorted { $0.rssi > $1.rssi }
        case .name:
            return searched.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            filterSection
            Divider().background(Color.appBorder)
            deviceListSection
            statusBar
        }
        .background(Color.appSurface)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            // Animated Bluetooth icon
            ZStack {
                if manager.isScanning {
                    Circle()
                        .stroke(Color.appAccent.opacity(pulseOpacity), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                        .scaleEffect(pulseScale)
                        .onAppear { startPulse() }
                        .onChange(of: manager.isScanning) { scanning in
                            if !scanning { stopPulse() }
                        }
                }
                Circle()
                    .fill(Color.appAccent.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.appAccent, Color.appAccent2],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("BLE Scanner")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(manager.isScanning ? Color.appSuccess : Color.textTertiary)
                        .frame(width: 5, height: 5)
                    Text(manager.isScanning
                         ? "스캔 중... \(manager.devices.count)개 발견"
                         : "\(manager.devices.count)개 기기")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            // Scan toggle button
            Button {
                if manager.isScanning { manager.stopScanning() }
                else { manager.startScanning() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: manager.isScanning ? "stop.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(manager.isScanning ? "중지" : "스캔")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(manager.isScanning ? .appError : .appAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((manager.isScanning ? Color.appError : Color.appAccent).opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke((manager.isScanning ? Color.appError : Color.appAccent).opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        VStack(spacing: 8) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                TextField("기기 이름 검색...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.textPrimary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.appBackground.opacity(0.6))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))

            // Service UUID filter
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12))
                    .foregroundColor(.textTertiary)
                TextField("Service UUID 필터 (예: 180D)", text: $manager.filterServiceUUID)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.appAccent)
                    .onSubmit {
                        if manager.isScanning {
                            manager.stopScanning()
                            manager.startScanning()
                        }
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.appBackground.opacity(0.6))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))

            // Options
            HStack(spacing: 12) {
                Toggle(isOn: $manager.autoSubscribeNotify) {
                    Text("자동 알림 구독")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                }
                .toggleStyle(CompactToggleStyle())

                Toggle(isOn: $manager.showOnlyConnectable) {
                    Text("연결 가능만")
                        .font(.system(size: 11))
                        .foregroundColor(.textSecondary)
                }
                .toggleStyle(CompactToggleStyle())

                Spacer()

                // Sort order picker
                Menu {
                    ForEach(DeviceSortOrder.allCases, id: \.self) { order in
                        Button {
                            withAnimation(.spring(response: 0.3)) { sortOrder = order }
                        } label: {
                            HStack {
                                Image(systemName: order.icon)
                                Text(order.rawValue)
                                if sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: sortOrder.icon)
                            .font(.system(size: 10, weight: .medium))
                        Text(sortOrder.rawValue)
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundColor(.appAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.appAccent.opacity(0.1))
                    .cornerRadius(7)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.appAccent.opacity(0.25), lineWidth: 1))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Device List

    private var deviceListSection: some View {
        Group {
            if filteredDevices.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredDevices) { device in
                            DeviceRowView(
                                device: device,
                                isSelected: manager.selectedDevice?.id == device.id,
                                onTap: { manager.selectedDevice = device }
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .animation(.spring(response: 0.35), value: filteredDevices.map { $0.id })
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(0.05))
                    .frame(width: 80, height: 80)
                Image(systemName: manager.isScanning
                      ? "antenna.radiowaves.left.and.right"
                      : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 32))
                    .foregroundColor(manager.isScanning ? .appAccent : .textTertiary)
                    .opacity(manager.isScanning ? (pulseOpacity > 0.3 ? 1.0 : 0.5) : 0.4)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseOpacity)
            }
            Text(manager.isScanning ? "기기 검색 중..." : "스캔을 시작하세요")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.textSecondary)
            Text(manager.isScanning
                 ? "주변의 BLE 기기가 감지되면\n여기에 표시됩니다."
                 : "상단의 [스캔] 버튼을 눌러\n주변 BLE 기기를 검색합니다.")
                .font(.system(size: 11))
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            // Bluetooth state indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(bluetoothStateColor)
                    .frame(width: 6, height: 6)
                Text(bluetoothStateText)
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }
            Spacer()
            Text("발견: \(manager.devices.count)")
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.appBackground.opacity(0.5))
    }

    private var bluetoothStateColor: Color {
        switch manager.bluetoothState {
        case .poweredOn:  return .appSuccess
        case .poweredOff: return .appError
        default:          return .appWarning
        }
    }

    private var bluetoothStateText: String {
        switch manager.bluetoothState {
        case .poweredOn:      return "BT 활성"
        case .poweredOff:     return "BT 꺼짐"
        case .unauthorized:   return "권한 없음"
        case .unsupported:    return "미지원"
        case .resetting:      return "재설정 중"
        default:              return "초기화 중"
        }
    }

    // MARK: - Animation Helpers

    private func startPulse() {
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            pulseScale = 1.6
            pulseOpacity = 0.6
        }
    }

    private func stopPulse() {
        withAnimation(.easeOut(duration: 0.3)) {
            pulseScale = 1.0
            pulseOpacity = 0.0
        }
    }
}

// MARK: - Compact Toggle Style

struct CompactToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 4)
                .fill(configuration.isOn ? Color.appAccent : Color.appBorder)
                .frame(width: 24, height: 14)
                .overlay(
                    Circle()
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .offset(x: configuration.isOn ? 5 : -5)
                        .animation(.spring(response: 0.2), value: configuration.isOn)
                )
                .onTapGesture { configuration.isOn.toggle() }
            configuration.label
        }
    }
}
