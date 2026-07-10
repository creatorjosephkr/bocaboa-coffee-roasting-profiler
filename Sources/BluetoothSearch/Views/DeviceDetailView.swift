import SwiftUI

// MARK: - Device Detail View

struct DeviceDetailView: View {
    @ObservedObject var manager: BluetoothManager

    var body: some View {
        Group {
            if let device = manager.selectedDevice {
                SelectedDeviceView(manager: manager, device: device)
            } else {
                noSelectionView
            }
        }
        .background(Color.appBackground)
    }

    private var noSelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(colors: [.appAccent, .appAccent2], startPoint: .top, endPoint: .bottom)
                )
                .opacity(0.3)
            Text("기기를 선택하세요")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.textSecondary)
            Text("왼쪽 목록에서 BLE 기기를 선택하면\n서비스와 특성 정보가 표시됩니다.")
                .font(.system(size: 12))
                .foregroundColor(.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Selected Device View

struct SelectedDeviceView: View {
    @ObservedObject var manager: BluetoothManager
    @ObservedObject var device: BLEDevice
    @EnvironmentObject var nicknameStore: NicknameStore

    @State private var isEditingNickname: Bool = false
    @State private var nicknameInput: String = ""
    @FocusState private var isNicknameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            deviceHeader
                .zIndex(1)
                .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
            
            Divider().background(Color.appBorder)
            
            if device.status.isConnected {
                servicesContent
            } else {
                notConnectedView
            }
        }
    }

    // MARK: - Device Header

    private var deviceHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Device icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [Color.appAccent.opacity(0.2), Color.appAccent2.opacity(0.15)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.appAccent.opacity(0.3), lineWidth: 1)
                        .frame(width: 52, height: 52)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.appAccent, .appAccent2],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }

                // Device info + nickname
                VStack(alignment: .leading, spacing: 4) {
                    // 별명이 있으면 별명을 주 이름으로 표시
                    let nickname = nicknameStore.nickname(for: device.peripheralUUID)
                    if let nick = nickname {
                        Text(nick)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text(device.name)
                            .font(.system(size: 11))
                            .foregroundColor(.textTertiary)
                    } else {
                        Text(device.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.textPrimary)
                    }
                    StatusBadge(status: device.status)
                }

                Spacer()

                // Signal strength
                VStack(spacing: 4) {
                    SignalBarsView(strength: device.rssiStrength, color: device.rssiColor, size: 18)
                    Text("\(device.rssi) dBm")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(device.rssiColor)
                }

                // Connect / Disconnect button
                connectButton
            }

            // Nickname editor row
            nicknameEditorRow

            // Device meta info
            deviceInfoGrid
        }
        .padding(16)
        .background(Color.appSurface)
    }

    // MARK: - Nickname Editor

    private var nicknameEditorRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "tag.fill")
                .font(.system(size: 11))
                .foregroundColor(isEditingNickname ? .appDiscovered : .textTertiary)

            if isEditingNickname {
                // 편집 모드
                TextField("별명 입력 (예: 커피 로스터)", text: $nicknameInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.textPrimary)
                    .focused($isNicknameFocused)
                    .onSubmit { saveNickname() }

                // 저장
                Button { saveNickname() } label: {
                    Text("저장")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.appSuccess)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.appSuccess.opacity(0.12))
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.appSuccess.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])

                // 취소
                Button { cancelNicknameEdit() } label: {
                    Text("취소")
                        .font(.system(size: 11))
                        .foregroundColor(.textTertiary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

            } else {
                // 표시 모드
                let nickname = nicknameStore.nickname(for: device.peripheralUUID)
                if let nick = nickname {
                    Text(nick)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.appDiscovered)

                    // 수정 버튼
                    Button { startNicknameEdit() } label: {
                        Text("장치이름 변경")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.appAccent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.appAccent.opacity(0.12))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("별명 수정")

                    // 삭제 버튼
                    Button {
                        withAnimation { nicknameStore.removeNickname(for: device.peripheralUUID) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.textTertiary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("별명 삭제")

                } else {
                    // 별명 없음 → 추가 버튼
                    Button { startNicknameEdit() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 10))
                            Text("별명 추가...")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("기기에 별명을 지정합니다. 앱을 재시작해도 유지됩니다.")
                }
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.appBackground.opacity(0.4))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(isEditingNickname ? Color.appDiscovered.opacity(0.4) : Color.appBorder, lineWidth: 1))
        .animation(.spring(response: 0.25), value: isEditingNickname)
    }

    // MARK: - Nickname Helpers

    private func startNicknameEdit() {
        nicknameInput = nicknameStore.nickname(for: device.peripheralUUID) ?? ""
        isEditingNickname = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isNicknameFocused = true
        }
    }

    private func saveNickname() {
        nicknameStore.setNickname(nicknameInput, for: device.peripheralUUID)
        isEditingNickname = false
        isNicknameFocused = false
    }

    private func cancelNicknameEdit() {
        isEditingNickname = false
        isNicknameFocused = false
        nicknameInput = ""
    }

    private var connectButton: some View {
        Group {
            if device.status == .connecting {
                Button { manager.disconnect(device) } label: {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.65).tint(.appWarning)
                        Text("연결 중")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.appWarning)
                        Text("취소")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.appWarning.opacity(0.7))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.appWarning.opacity(0.15))
                            .cornerRadius(5)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.appWarning.opacity(0.1))
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.appWarning.opacity(0.3), lineWidth: 1))
            } else if device.status.isConnected {
                Button { manager.disconnect(device) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                        Text("해제")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.appError)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.appError.opacity(0.1))
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.appError.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                Button { manager.connect(device) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .bold))
                        Text("연결")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.appAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.appAccent.opacity(0.12))
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.appAccent.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!device.isConnectable)
            }
        }
    }

    private var deviceInfoGrid: some View {
        VStack(spacing: 8) {
            // Full UUID row
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DEVICE UUID")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.textTertiary)
                    Text(device.peripheralUUID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.appAccent)
                        .textSelection(.enabled)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appBackground.opacity(0.5))
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.appAccent.opacity(0.2), lineWidth: 1))

                VStack(alignment: .leading, spacing: 3) {
                    Text("RSSI")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.textTertiary)
                    Text("\(device.rssi) dBm (\(device.rssiDescription))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(device.rssiColor)
                }
                .padding(8)
                .frame(width: 140, alignment: .leading)
                .background(Color.appBackground.opacity(0.5))
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.appBorder, lineWidth: 1))
            }

            // Advertisement data grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 6) {
                InfoCell(label: "연결 가능", value: device.isConnectable ? "✓ 예" : "✗ 아니오")
                if let txPower = device.txPowerLevel {
                    InfoCell(label: "Tx Power", value: "\(txPower) dBm")
                }
                if !device.manufacturerDataHex.isEmpty && device.manufacturerDataHex != "-" {
                    InfoCell(label: "제조사 데이터 (HEX)", value: device.manufacturerDataHex)
                }
            }

            // Advertised Service UUIDs
            if !device.advertisedServiceUUIDs.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("광고 SERVICE UUID")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.textTertiary)
                    ForEach(device.advertisedServiceUUIDs, id: \.uuidString) { uuid in
                        HStack(spacing: 8) {
                            Text(uuid.uuidString)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.textSecondary)
                                .textSelection(.enabled)
                            let name = BluetoothUUIDHelper.serviceName(for: uuid)
                            if let name = name {
                                Text(name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.appAccent)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.appAccent.opacity(0.1))
                                    .cornerRadius(4)
                            } else {
                                Text("Custom")
                                    .font(.system(size: 10))
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appBackground.opacity(0.5))
                .cornerRadius(7)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.appBorder, lineWidth: 1))
            }
        }
    }

    // MARK: - Not Connected

    private var notConnectedView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Connect hint
                VStack(spacing: 10) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(LinearGradient(colors: [.appAccent, .appAccent2],
                                                        startPoint: .top, endPoint: .bottom))
                        .opacity(0.6)
                    Text("연결되지 않음")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textSecondary)
                    Text("위의 [연결] 버튼을 눌러 기기에 연결하면\nService와 Characteristic 정보가 표시됩니다.")
                        .font(.system(size: 12))
                        .foregroundColor(.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 30)

                // Raw advertisement data panel
                AdvertisementDataView(device: device)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground)
    }

    // MARK: - Services Content

    private var servicesContent: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 온도 데이터가 이 기기에서 수신된 경우 모니터 표시
                if !manager.temperatureHistory.filter({ $0.deviceName == device.name }).isEmpty {
                    TemperatureMonitorView(manager: manager)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if device.services.isEmpty {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("서비스 검색 중...")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                    .padding(.top, 20)
                } else {
                    ForEach(device.services) { service in
                        ServiceSectionView(
                            service: service,
                            peripheral: device.peripheral,
                            manager: manager
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .padding(14)
            .animation(.spring(response: 0.4), value: device.services.count)
            .animation(.spring(response: 0.5), value: manager.temperatureHistory.count)
        }
        .background(Color.appBackground)
    }

}

// MARK: - Service Section View

struct ServiceSectionView: View {
    @ObservedObject var service: BLEService
    let peripheral: CBPeripheral
    let manager: BluetoothManager

    var body: some View {
        VStack(spacing: 0) {
            // Service header
            serviceHeader
                .onTapGesture { withAnimation(.spring(response: 0.3)) { service.isExpanded.toggle() } }

            if service.isExpanded {
                VStack(spacing: 1) {
                    if service.characteristics.isEmpty {
                        HStack {
                            ProgressView().scaleEffect(0.6)
                            Text("특성 검색 중...")
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                        }
                        .padding(.vertical, 12)
                    } else {
                        ForEach(service.characteristics) { char in
                            CharacteristicRowView(
                                characteristic: char,
                                peripheral: peripheral,
                                manager: manager
                            )
                            if char.id != service.characteristics.last?.id {
                                Divider()
                                    .background(Color.appBorder)
                                    .padding(.horizontal, 12)
                            }
                        }
                    }
                }
                .background(Color.appSurface.opacity(0.5))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color.appSurface2)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
        .clipped()
    }

    private var serviceHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: service.isStandard ? "shield.fill" : "cpu")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(service.isStandard ? .appAccent : .appDiscovered)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text(service.uuid)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.textTertiary)
            }

            Spacer()

            HStack(spacing: 6) {
                if service.isStandard {
                    Text("GATT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.appAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.appAccent.opacity(0.12))
                        .cornerRadius(4)
                }
                Text("\(service.characteristics.count) char")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)

                Image(systemName: service.isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Characteristic Row View

struct CharacteristicRowView: View {
    @ObservedObject var characteristic: BLECharacteristic
    let peripheral: CBPeripheral
    let manager: BluetoothManager

    @State private var displayFormat: DataDisplayFormat = .hex
    @State private var writeInput: String = ""
    @State private var isExpanded: Bool = false
    @State private var flashUpdate: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            mainRow
                .onTapGesture {
                    withAnimation(.spring(response: 0.25)) { isExpanded.toggle() }
                }

            if isExpanded {
                expandedContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: characteristic.updateCount) { _ in
            flashValue()
        }
    }

    private var mainRow: some View {
        HStack(spacing: 10) {
            // Notify indicator dot
            Circle()
                .fill(characteristic.isNotifying ? Color.appSuccess : Color.clear)
                .frame(width: 6, height: 6)
                .overlay(
                    Circle()
                        .stroke(characteristic.isNotifying ? Color.appSuccess : Color.textTertiary, lineWidth: 1)
                        .frame(width: 6, height: 6)
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(characteristic.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    if characteristic.updateCount > 0 {
                        Text("×\(characteristic.updateCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.appData)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.appData.opacity(0.12))
                            .cornerRadius(3)
                    }
                }

                // Properties badges
                HStack(spacing: 4) {
                    ForEach(characteristic.properties, id: \.rawValue) { prop in
                        Text(prop.rawValue)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(prop.color)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(prop.color.opacity(0.12))
                            .cornerRadius(3)
                    }
                }
            }

            Spacer()

            // Value preview
            VStack(alignment: .trailing, spacing: 2) {
                Text(characteristic.formattedValue(as: displayFormat))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(flashUpdate ? .appData : .textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .animation(.easeOut(duration: 0.3), value: flashUpdate)

                if let updated = characteristic.lastUpdated {
                    Text(timeAgoString(updated))
                        .font(.system(size: 9))
                        .foregroundColor(.textTertiary)
                }
            }
            .frame(maxWidth: 140, alignment: .trailing)

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var expandedContent: some View {
        VStack(spacing: 10) {
            Divider().background(Color.appBorder).padding(.horizontal, 14)

            VStack(spacing: 8) {
                // UUID
                HStack {
                    Text("UUID")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.textTertiary)
                    Spacer()
                    Text(characteristic.uuid)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.textSecondary)
                        .textSelection(.enabled)
                }

                // Value with format toggle
                if characteristic.value != nil {
                    VStack(spacing: 6) {
                        HStack {
                            Text("값 (\(characteristic.byteCount) bytes)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.textTertiary)
                            Spacer()
                            // Format picker
                            Picker("", selection: $displayFormat) {
                                ForEach(DataDisplayFormat.allCases, id: \.self) { fmt in
                                    Text(fmt.rawValue).tag(fmt)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                        }
                        Text(characteristic.formattedValue(as: displayFormat))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.appData)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.appBackground)
                            .cornerRadius(6)
                            .textSelection(.enabled)
                    }
                }

                // Actions
                HStack(spacing: 8) {
                    if characteristic.canRead {
                        ActionButton(
                            label: "읽기",
                            icon: "arrow.down.circle",
                            color: .appAccent
                        ) {
                            manager.readValue(for: characteristic, peripheral: peripheral)
                        }
                    }
                    if characteristic.canNotify {
                        ActionButton(
                            label: characteristic.isNotifying ? "알림 끄기" : "알림 켜기",
                            icon: characteristic.isNotifying ? "bell.slash.fill" : "bell.fill",
                            color: characteristic.isNotifying ? .appWarning : .appSuccess
                        ) {
                            manager.toggleNotify(for: characteristic, peripheral: peripheral)
                        }
                    }
                    Spacer()
                }

                // Write input
                if characteristic.canWrite {
                    HStack(spacing: 8) {
                        TextField("HEX 값 입력 (예: 01 FF A0)", text: $writeInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.appBackground)
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appBorder, lineWidth: 1))

                        Button {
                            if let data = hexStringToData(writeInput) {
                                manager.writeValue(data, for: characteristic, peripheral: peripheral)
                                writeInput = ""
                            }
                        } label: {
                            Text("쓰기")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.appWarning)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.appWarning.opacity(0.12))
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appWarning.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(writeInput.isEmpty)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .background(Color.appBackground.opacity(0.4))
    }

    // MARK: - Helpers

    private func flashValue() {
        withAnimation { flashUpdate = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation { flashUpdate = false }
        }
    }

    private func timeAgoString(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)초 전" }
        return "\(seconds / 60)분 전"
    }

    private func hexStringToData(_ hex: String) -> Data? {
        let cleaned = hex.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "0x", with: "")
            .replacingOccurrences(of: "0X", with: "")
        guard cleaned.count % 2 == 0 else { return nil }
        var data = Data()
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let byte = UInt8(cleaned[idx..<next], radix: 16) else { return nil }
            data.append(byte)
            idx = next
        }
        return data
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let label: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.1))
            .cornerRadius(7)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info Cell

struct InfoCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.textTertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.textSecondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground.opacity(0.5))
        .cornerRadius(7)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.appBorder, lineWidth: 1))
    }
}

// MARK: - Advertisement Data View

struct AdvertisementDataView: View {
    @ObservedObject var device: BLEDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.appDiscovered)
                Text("Advertisement Data")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("Raw scan data")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }

            // All advertisement fields
            VStack(spacing: 6) {
                advRow(key: "Local Name",
                       value: device.advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "—")
                advRow(key: "Peripheral Name",
                       value: device.peripheral.name ?? "—")
                advRow(key: "Device UUID (OS 생성)",
                       value: device.peripheralUUID,
                       isHighlight: true)

                if let mfData = device.manufacturerData {
                    let company = companyName(from: mfData)
                    advRow(key: "Manufacturer Data (HEX)",
                           value: device.manufacturerDataHex +
                                  (company != nil ? "  →  \(company!)" : ""))
                }

                let serviceUUIDs = device.advertisedServiceUUIDs
                if !serviceUUIDs.isEmpty {
                    advRow(key: "Service UUIDs",
                           value: serviceUUIDs.map { uuid in
                               let name = BluetoothUUIDHelper.serviceName(for: uuid)
                               return name != nil ? "\(uuid.uuidString) (\(name!))" : uuid.uuidString
                           }.joined(separator: "\n"))
                }

                if let txPower = device.txPowerLevel {
                    advRow(key: "Tx Power Level", value: "\(txPower) dBm")
                }

                advRow(key: "Connectable", value: device.isConnectable ? "✓ 예" : "✗ 아니오")
                advRow(key: "RSSI", value: "\(device.rssi) dBm")
                advRow(key: "마지막 감지", value: timeString(device.lastSeen))
            }

            // BOCA device hint
            if device.name.uppercased().contains("BOCA") || device.name.uppercased().hasPrefix("BT_") {
                bocaHint
            }
        }
        .padding(12)
        .background(Color.appSurface2)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appDiscovered.opacity(0.2), lineWidth: 1))
    }

    private func advRow(key: String, value: String, isHighlight: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(key)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textTertiary)
                .frame(width: 140, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(isHighlight ? .appAccent : .textSecondary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
        .background(isHighlight ? Color.appAccent.opacity(0.06) : Color.clear)
        .cornerRadius(5)
    }

    private var bocaHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "cup.and.heat.waves.fill")
                .font(.system(size: 13))
                .foregroundColor(.appWarning)
            VStack(alignment: .leading, spacing: 3) {
                Text("BOCA 커피 로스터 기기 감지됨")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.appWarning)
                Text("전용 앱의 연결을 먼저 해제한 후 이 앱에서 연결하세요.\n기기는 한 번에 하나의 앱에서만 연결 가능합니다.")
                    .font(.system(size: 10))
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(10)
        .background(Color.appWarning.opacity(0.08))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appWarning.opacity(0.25), lineWidth: 1))
    }

    private func companyName(from data: Data) -> String? {
        guard data.count >= 2 else { return nil }
        let companyID = UInt16(data[0]) | (UInt16(data[1]) << 8)
        let known: [UInt16: String] = [
            0x004C: "Apple",
            0x0006: "Microsoft",
            0x0075: "Samsung",
            0x0059: "Nordic Semiconductor",
            0x0499: "Ruuvi Innovations",
            0x0157: "Bose",
            0x038F: "Google",
        ]
        return known[companyID]
    }

    private func timeString(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5  { return "방금" }
        if seconds < 60 { return "\(seconds)초 전" }
        return "\(seconds / 60)분 전"
    }
}

// MARK: - CBPeripheral Extension (for reference)
import CoreBluetooth
