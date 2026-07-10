import SwiftUI
import Charts

// MARK: - Temperature Monitor View

struct TemperatureMonitorView: View {
    @ObservedObject var manager: BluetoothManager
    @State private var showPacketFormat: Bool = false
    @State private var selectedUnit: TempUnit = .celsius

    enum TempUnit: String, CaseIterable {
        case celsius    = "°C"
        case fahrenheit = "°F"
    }

    // 현재 온도 (가장 최근 값)
    private var currentEntry: TemperatureEntry? { manager.temperatureHistory.first }

    private var currentTemp: Double? {
        guard let e = currentEntry else { return nil }
        return selectedUnit == .celsius ? e.celsius : e.fahrenheit
    }

    // 세션 통계
    private var minTemp: Double? {
        let vals = manager.temperatureHistory.map { selectedUnit == .celsius ? $0.celsius : $0.fahrenheit }
        return vals.min()
    }
    private var maxTemp: Double? {
        let vals = manager.temperatureHistory.map { selectedUnit == .celsius ? $0.celsius : $0.fahrenheit }
        return vals.max()
    }
    private var avgTemp: Double? {
        guard !manager.temperatureHistory.isEmpty else { return nil }
        let sum = manager.temperatureHistory.reduce(0.0) { $0 + (selectedUnit == .celsius ? $1.celsius : $1.fahrenheit) }
        return sum / Double(manager.temperatureHistory.count)
    }

    // 차트 표시용 (최근 60개, 오름차순 시간)
    private var chartData: [TemperatureEntry] {
        Array(manager.temperatureHistory.prefix(60).reversed())
    }

    // 차트 Y축 범위
    private var yRange: ClosedRange<Double> {
        let allVals = chartData.map { selectedUnit == .celsius ? $0.celsius : $0.fahrenheit }
        let lo = (allVals.min() ?? 0) - 5
        let hi = (allVals.max() ?? 100) + 5
        return lo...hi
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            VStack(spacing: 12) {
                // Current temperature + stats
                HStack(alignment: .top, spacing: 16) {
                    currentTempDisplay
                    Spacer()
                    statsPanel
                }

                // Chart
                if chartData.count >= 2 {
                    temperatureChart
                }

                // Packet format decoder (collapsible)
                packetFormatPanel
            }
            .padding(14)
        }
        .background(Color.appSurface2)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(
            LinearGradient(colors: [.appError.opacity(0.4), .appWarning.opacity(0.3)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1))
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(colors: [.appWarning, .appError],
                                   startPoint: .bottom, endPoint: .top)
                )
            Text("온도 모니터")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textPrimary)

            Text("BOCA 프로토콜")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.appWarning)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.appWarning.opacity(0.12))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.appWarning.opacity(0.3), lineWidth: 1))

            Spacer()

            // 샘플 수
            Text("\(manager.temperatureHistory.count)개 수신")
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)

            // 단위 토글
            HStack(spacing: 0) {
                ForEach(TempUnit.allCases, id: \.self) { unit in
                    Button { withAnimation { selectedUnit = unit } } label: {
                        Text(unit.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(selectedUnit == unit ? .appBackground : .textTertiary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(selectedUnit == unit ? Color.appWarning : Color.clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.appBackground)
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appBorder, lineWidth: 1))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.appSurface)
    }

    // MARK: - Current Temperature

    private var currentTempDisplay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("현재 온도")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textTertiary)

            if let temp = currentTemp {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(String(format: "%.0f", temp))
                        .font(.system(size: 52, weight: .bold, design: .monospaced))
                        .foregroundStyle(
                            LinearGradient(
                                colors: tempGradientColors(temp),
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                    Text(selectedUnit.rawValue)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.textSecondary)
                        .padding(.bottom, 8)
                }
                if let lastTime = currentEntry?.formattedTime {
                    Text("마지막 수신: \(lastTime)")
                        .font(.system(size: 10))
                        .foregroundColor(.textTertiary)
                }
            } else {
                Text("--")
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .foregroundColor(.textTertiary)
                Text("데이터 대기 중...")
                    .font(.system(size: 10))
                    .foregroundColor(.textTertiary)
            }
        }
    }

    // MARK: - Stats Panel

    private var statsPanel: some View {
        VStack(alignment: .trailing, spacing: 6) {
            statRow(label: "최고", value: maxTemp, icon: "arrow.up", color: .appError)
            statRow(label: "최저", value: minTemp, icon: "arrow.down", color: .appAccent)
            statRow(label: "평균", value: avgTemp, icon: "equal", color: .textSecondary)
        }
    }

    private func statRow(label: String, value: Double?, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.textTertiary)
            if let v = value {
                Text(String(format: "%.0f%@", v, selectedUnit.rawValue))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(color)
            } else {
                Text("--")
                    .font(.system(size: 13))
                    .foregroundColor(.textTertiary)
            }
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.07))
        .cornerRadius(6)
    }

    // MARK: - Temperature Chart

    private var temperatureChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("온도 추이 (최근 \(chartData.count)회)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.textTertiary)

            Chart {
                // Area fill
                ForEach(chartData) { entry in
                    AreaMark(
                        x: .value("시간", entry.timestamp),
                        y: .value(selectedUnit.rawValue,
                                  selectedUnit == .celsius ? entry.celsius : entry.fahrenheit)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.appError.opacity(0.25), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
                // Line
                ForEach(chartData) { entry in
                    LineMark(
                        x: .value("시간", entry.timestamp),
                        y: .value(selectedUnit.rawValue,
                                  selectedUnit == .celsius ? entry.celsius : entry.fahrenheit)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.appWarning, .appError],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                // Latest point
                if let latest = chartData.last {
                    PointMark(
                        x: .value("시간", latest.timestamp),
                        y: .value(selectedUnit.rawValue,
                                  selectedUnit == .celsius ? latest.celsius : latest.fahrenheit)
                    )
                    .foregroundStyle(Color.appError)
                    .symbolSize(30)
                }
            }
            .chartYScale(domain: yRange)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.appBorder)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(String(format: "%.0f%@", v, selectedUnit.rawValue))
                                .font(.system(size: 9))
                                .foregroundColor(.textTertiary)
                        }
                    }
                }
            }
            .frame(height: 110)
            .padding(.leading, 4)
        }
    }

    // MARK: - Packet Format Panel

    private var packetFormatPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toggle header
            Button {
                withAnimation(.spring(response: 0.3)) { showPacketFormat.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.textTertiary)
                        .rotationEffect(.degrees(showPacketFormat ? 90 : 0))
                    Text("패킷 포맷 분석")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.textTertiary)
                    Spacer()
                    if let data = manager.temperatureHistory.first.map({ _ in
                        // Show last raw bytes from log for reference
                        return "FE EF 01 01 HH LL 00 00 EF FE"
                    }) {
                        Text(data)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.textTertiary.opacity(0.7))
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.appBackground.opacity(0.4))
            .cornerRadius(8)

            if showPacketFormat {
                VStack(spacing: 0) {
                    // Field table
                    let fields: [(String, String, Color)] = [
                        ("0–1", "FE EF",      .textTertiary),
                        ("2",   "01",         .textTertiary),
                        ("3",   "01",         .textTertiary),
                        ("4",   "HH 온도",    .appWarning),
                        ("5",   "LL 온도",    .appWarning),
                        ("6-7", "배터리 추정", .appSuccess),
                        ("8–9", "EF FE",      .textTertiary),
                    ]
                    let labels = ["Start Frame", "Protocol Ver", "Msg Type",
                                  "Temp High byte", "Temp Low byte",
                                  "Battery (6: %, 7: 상태)", "End Frame"]

                    VStack(spacing: 0) {
                        // Byte blocks visualization
                        HStack(spacing: 2) {
                            ForEach(Array(zip(fields, labels)), id: \.0.0) { (field, label) in
                                VStack(spacing: 2) {
                                    Text(field.1)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(field.2)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                        .background(field.2.opacity(0.1))
                                        .cornerRadius(4)
                                    Text(label)
                                        .font(.system(size: 7))
                                        .foregroundColor(.textTertiary)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.top, 8)
                        .padding(.bottom, 6)

                        Divider().background(Color.appBorder).padding(.horizontal, 6)

                        // Formula explanation
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "function")
                                    .font(.system(size: 10))
                                    .foregroundColor(.appWarning)
                                Text("공식:  raw = uint16_BE(byte[4], byte[5])   →   temp°C = (raw - 42) / 32")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.textSecondary)
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "battery.100")
                                    .font(.system(size: 10))
                                    .foregroundColor(.appSuccess)
                                Text("배터리: byte[6] = 백분율(%), byte[7] = 상태 데이터")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.textSecondary)
                            }
                            if let entry = manager.temperatureHistory.first {
                                let rawApprox = Int(entry.celsius * 32 + 42)
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.appSuccess)
                                    Text("현재: raw ≈ \(rawApprox)  →  (\(rawApprox)-42)/32 = \(String(format: "%.1f", entry.celsius))°C")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.appSuccess)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                    .background(Color.appBackground.opacity(0.4))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                    .padding(.top, 4)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Helpers

    private func tempGradientColors(_ temp: Double) -> [Color] {
        let celsius = selectedUnit == .celsius ? temp : (temp - 32) * 5 / 9
        switch celsius {
        case ..<50:   return [.appAccent, .appAccent2]
        case 50..<100: return [.appWarning, .appWarning.opacity(0.7)]
        case 100..<150: return [.appWarning, .appError]
        default:      return [.appError, .red]
        }
    }
}
