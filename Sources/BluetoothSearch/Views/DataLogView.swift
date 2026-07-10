import SwiftUI
import AppKit

// MARK: - Data Log View

struct DataLogView: View {
    @ObservedObject var manager: BluetoothManager
    @State private var autoScroll: Bool = true
    @State private var filterType: LogEntry.LogType? = nil
    @State private var showOnlyConnectedDevice: Bool = true
    @State private var scrollProxy: ScrollViewProxy? = nil

    // 현재 연결된 기기 이름 (연결됨 상태인 selectedDevice)
    private var connectedDeviceName: String? {
        guard let device = manager.selectedDevice, device.status.isConnected else { return nil }
        return device.name
    }

    private var displayedLogs: [LogEntry] {
        var logs = manager.logs

        // 1. 연결된 기기 필터 (연결 중인 기기가 있고, 필터 ON일 때)
        if showOnlyConnectedDevice, let devName = connectedDeviceName {
            logs = logs.filter { $0.deviceName == devName }
        }

        // 2. 타입 필터
        if let type = filterType {
            logs = logs.filter { $0.type == type }
        }

        return logs
    }

    private var isDeviceFilterActive: Bool {
        showOnlyConnectedDevice && connectedDeviceName != nil
    }


    var body: some View {
        VStack(spacing: 0) {
            logHeader
            Divider().background(Color.appBorder)
            logContent
        }
        .background(Color.appSurface)
    }

    // MARK: - Header

    private var logHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [.appAccent, .appAccent2], startPoint: .leading, endPoint: .trailing)
                )

            Text("이벤트 로그")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textPrimary)

            // 전체 로그 수
            Text("\(manager.logs.count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.appAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.appAccent.opacity(0.12))
                .cornerRadius(5)

            // 연결 기기 필터 배지 (활성 시 표시)
            if isDeviceFilterActive, let devName = connectedDeviceName {
                HStack(spacing: 4) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 10))
                    Text(devName)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Text("만 표시 중")
                        .font(.system(size: 10))
                        .foregroundColor(.appSuccess.opacity(0.7))
                }
                .foregroundColor(.appSuccess)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.appSuccess.opacity(0.1))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appSuccess.opacity(0.3), lineWidth: 1))
                .transition(.scale.combined(with: .opacity))
            }

            // 표시 건수 (필터링된 경우)
            if displayedLogs.count != manager.logs.count {
                Text("표시: \(displayedLogs.count)")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }

            Spacer()

            // Filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    FilterPill(label: "ALL", isSelected: filterType == nil, color: .textSecondary) {
                        filterType = nil
                    }
                    ForEach([LogEntry.LogType.data, .connected, .discovered, .info, .warning, .error], id: \.rawValue) { type in
                        FilterPill(
                            label: type.rawValue,
                            isSelected: filterType == type,
                            color: type.color
                        ) {
                            filterType = (filterType == type) ? nil : type
                        }
                    }
                }
            }
            .frame(maxWidth: 300)

            Divider().frame(height: 16).background(Color.appBorder)

            // 기기 로그 필터 토글 (연결된 기기 있을 때만 의미 있음)
            Button {
                withAnimation(.spring(response: 0.25)) {
                    showOnlyConnectedDevice.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showOnlyConnectedDevice ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(.system(size: 12))
                    Text(showOnlyConnectedDevice ? "현재 기기" : "전체")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(isDeviceFilterActive ? .appSuccess : (connectedDeviceName != nil ? .appSuccess.opacity(0.5) : .textTertiary))
            }
            .buttonStyle(.plain)
            .help(connectedDeviceName != nil
                  ? (showOnlyConnectedDevice ? "전체 로그 보기" : "연결된 기기 로그만 보기")
                  : "기기 연결 시 사용 가능")
            .disabled(connectedDeviceName == nil)

            // Auto scroll toggle
            Button {
                autoScroll.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 12))
                    Text("자동")
                        .font(.system(size: 11))
                }
                .foregroundColor(autoScroll ? .appAccent : .textTertiary)
            }
            .buttonStyle(.plain)


            // Export button
            Button {
                exportLogs()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12))
                    Text("내보내기")
                        .font(.system(size: 11))
                }
                .foregroundColor(.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(manager.logs.isEmpty)

            // Clear button
            Button {
                withAnimation { manager.clearLogs() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                    Text("지우기")
                        .font(.system(size: 11))
                }
                .foregroundColor(.appError)
            }
            .buttonStyle(.plain)
            .disabled(manager.logs.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.appSurface)
    }

    // MARK: - Log Content

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayedLogs) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                        if entry.id != displayedLogs.last?.id {
                            Divider()
                                .background(Color.appBorder.opacity(0.5))
                                .padding(.leading, 40)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .background(Color.appBackground)
            .onAppear { scrollProxy = proxy }
            .onChange(of: manager.logs.first?.id) { _ in
                if autoScroll, let first = displayedLogs.first {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(first.id, anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - Export

    private func exportLogs() {
        let content = manager.exportLogs()
        let panel = NSSavePanel()
        panel.title = "로그 내보내기"
        panel.nameFieldStringValue = "ble_log_\(Int(Date().timeIntervalSince1970)).txt"
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Timestamp
            Text(entry.formattedTime)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(.textTertiary)
                .frame(width: 78, alignment: .leading)
                .padding(.top, 1)

            // Type badge
            Text(entry.type.rawValue)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundColor(entry.type.color)
                .frame(width: 36)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(entry.type.color.opacity(0.1))
                .cornerRadius(3)

            // Icon
            Image(systemName: entry.type.icon)
                .font(.system(size: 10))
                .foregroundColor(entry.type.color)
                .frame(width: 14)
                .padding(.top, 1)

            // Message
            VStack(alignment: .leading, spacing: 2) {
                if let device = entry.deviceName {
                    Text(device)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
                Text(entry.message)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.textPrimary)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(isSelected ? color : .textTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(isSelected ? color.opacity(0.15) : Color.clear)
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isSelected ? color.opacity(0.4) : Color.appBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.2), value: isSelected)
    }
}
