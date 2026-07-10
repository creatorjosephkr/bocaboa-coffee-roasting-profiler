import SwiftUI
import Charts
import AppKit

// MARK: - RoastReportView
// 세션 리포트를 SwiftUI로 렌더링하고, NSPrintOperation을 통해 PDF 저장 / 인쇄를 지원한다.

struct RoastReportView: View {
    let session: RoastSession
    let isForPrinting: Bool

    // 보정용 옵션 설정 상태
    @State private var rorWindowSize: Double
    @State private var rorFilterStrength: Double

    // 보정 처리된 세션 데이터
    @State private var correctedSession: RoastSession
    @State private var isZoomedGraphPresented = false
    @State private var memoText: String
    @State private var showMemoSavedToast = false

    init(session: RoastSession, isForPrinting: Bool = false) {
        self.session = session
        self.isForPrinting = isForPrinting
        _memoText = State(initialValue: session.memo ?? "")

        // UserDefaults에서 초기 설정값 로드
        let savedWindow = UserDefaults.standard.double(forKey: "rorWindowSize")
        let initialWindow = savedWindow > 0 ? savedWindow : 15.0

        let savedFilter = UserDefaults.standard.object(forKey: "rorFilterStrength") as? Double
        let initialFilter = savedFilter ?? 90.0

        _rorWindowSize = State(initialValue: initialWindow)
        _rorFilterStrength = State(initialValue: initialFilter)

        // 초기 보정된 세션 복제
        var initialSession = session
        
        // ─── 구버전 세션 시간축 보정 (투입 시점을 0초로 리셋) ───
        if let chargeEvent = initialSession.events.first(where: { $0.type == "생두 투입" || $0.type == "투입" || $0.type.contains("투입") }),
           chargeEvent.elapsedSeconds > 0 {
            let offset = chargeEvent.elapsedSeconds
            
            initialSession.events = initialSession.events.map { ev in
                var newEv = ev
                newEv.elapsedSeconds = ev.elapsedSeconds - offset
                return newEv
            }
            
            initialSession.graphPoints = initialSession.graphPoints.map { pt in
                var newPt = pt
                newPt.relativeTime = pt.relativeTime - offset
                return newPt
            }
        }
        
        Self.recalculateRoR(session: &initialSession, windowSize: initialWindow, filterStrength: initialFilter)
        _correctedSession = State(initialValue: initialSession)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ── 헤더 ──────────────────────────────────────────
            reportHeader

            Divider()

            // ── 요약 그리드 ───────────────────────────────────
            summaryGrid

            Divider()

            // ── 온도 그래프 ───────────────────────────────────
            temperatureChart
                .frame(height: 220)

            Divider()

            // ── 메모 영역 ─────────────────────────────────────
            memoArea

            Divider()

            // ── 이벤트 로그 ───────────────────────────────────
            eventTable

            Spacer()

            // ── 푸터 ──────────────────────────────────────────
            reportFooter
        }
        .padding(32)
        .background(Color.white)
        .preferredColorScheme(.light)
        .onChange(of: rorWindowSize) { newValue in
            UserDefaults.standard.set(newValue, forKey: "rorWindowSize")
            var updated = session
            Self.recalculateRoR(session: &updated, windowSize: newValue, filterStrength: rorFilterStrength)
            correctedSession = updated
        }
        .onChange(of: rorFilterStrength) { newValue in
            UserDefaults.standard.set(newValue, forKey: "rorFilterStrength")
            var updated = session
            Self.recalculateRoR(session: &updated, windowSize: rorWindowSize, filterStrength: newValue)
            correctedSession = updated
        }
        .sheet(isPresented: $isZoomedGraphPresented) {
            ZoomedGraphView(
                session: session,
                correctedSession: $correctedSession,
                rorWindowSize: $rorWindowSize,
                rorFilterStrength: $rorFilterStrength
            )
        }
    }

    // MARK: - Sub-views

    private var reportHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("🔥 로스팅 세션 리포트")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.black)
                Text(correctedSession.displayDate)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(correctedSession.beanName.isEmpty ? "원두명 미입력" : correctedSession.beanName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                Text("투입량: \(correctedSession.beanWeight)g  |  예열온도: \(correctedSession.preheatTemp)°C  |  목표 DTR: \(correctedSession.targetDTR)%")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
        }
    }

    private var summaryGrid: some View {
        let items: [(String, String)] = [
            ("실제 DTR", correctedSession.finalDTR.map { String(format: "%.1f%%", $0) } ?? "—"),
            ("총 로스팅 시간", correctedSession.totalRoastSeconds.map { formatSec($0) } ?? "—"),
            ("Develop Time", correctedSession.devTimeSeconds.map { formatSec($0) } ?? "—"),
            ("투입 온도", correctedSession.chargeTemp.map { String(format: "%.1f°C", $0) } ?? "—"),
            ("1차 팝 온도", correctedSession.firstPopTemp.map { String(format: "%.1f°C", $0) } ?? "—"),
            ("배출 온도", correctedSession.finishTemp.map { String(format: "%.1f°C", $0) } ?? "—"),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 12) {
            ForEach(items, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.gray)
                    Text(value)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.96))
                .cornerRadius(8)
            }
        }
    }

    private var temperatureChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("온도 프로파일")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gray)
                
                Spacer()
                
                // 인쇄/출력용이 아닌 경우에만 보정 슬라이더 표시
                if !isForPrinting {
                    HStack(spacing: 12) {
                        HStack(spacing: 3) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 10))
                                .foregroundColor(.appAccent)
                            Text("RoR 보정률:")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.appAccent)
                        }
                        
                        // 윈도우 조절
                        HStack(spacing: 4) {
                            Text("윈도우")
                                .font(.system(size: 10))
                                .foregroundColor(.textSecondary)
                            Slider(value: $rorWindowSize, in: 5.0...45.0, step: 1.0)
                                .frame(width: 80)
                            Text(String(format: "%.0f초", rorWindowSize))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.textPrimary)
                        }
                        
                        // 필터 조절
                        HStack(spacing: 4) {
                            Text("필터")
                                .font(.system(size: 10))
                                .foregroundColor(.textSecondary)
                            Slider(value: $rorFilterStrength, in: 0.0...95.0, step: 5.0)
                                .frame(width: 80)
                            Text(String(format: "%.0f%%", rorFilterStrength))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.textPrimary)
                        }
                        
                        // 초기화 버튼 (새로고침 아이콘)
                        Button(action: {
                            rorWindowSize = 15.0
                            rorFilterStrength = 90.0
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.appAccent)
                        }
                        .buttonStyle(.plain)
                        .help("RoR 설정 초기화 (시간: 15초, 필터: 90%)")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.appSurface2)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appBorder, lineWidth: 1))
                }
            }
            .padding(.bottom, 20) // 차트 위쪽 어노테이션 텍스트가 패널과 겹치지 않도록 충분한 여백 추가


            let minTime = correctedSession.graphPoints.map { $0.relativeTime }.min() ?? 0.0
            let maxTime = correctedSession.graphPoints.map { $0.relativeTime }.max() ?? 0.0

            let maxRoRInData = correctedSession.graphPoints.compactMap { $0.ror }.max() ?? 0.0
            let rawRorLimit = max(25.0, maxRoRInData)
            let rorLimit = ceil(rawRorLimit / 5.0) * 5.0 // 5의 배수로 올림하여 정갈한 눈금 유지
            let rorScaleFactor = 210.0 / rorLimit
            let rorTicks = stride(from: 0.0, through: rorLimit, by: 5.0).map { $0 }
            let rorDisplayTicks = rorTicks.map { $0 * rorScaleFactor + 20.0 }

            Chart {
                // 예열 영역 배경색 (연한 붉은색) - 투입(예열종료) 이벤트가 있는 경우에만 표시
                if correctedSession.events.first(where: { $0.type == "생두 투입" || $0.type == "투입" || $0.type.contains("투입") }) != nil {
                    if minTime < 0 {
                        RectangleMark(
                            xStart: .value("예열시작", minTime),
                            xEnd: .value("예열종료", 0.0),
                            yStart: .value("Y시작", 0.0),
                            yEnd: .value("Y종료", 240.0)
                        )
                        .foregroundStyle(Color.red.opacity(0.04))
                    }
                }
                
                ForEach(correctedSession.graphPoints) { pt in
                    LineMark(
                        x: .value("시간", pt.relativeTime),
                        y: .value("온도", pt.temperature),
                        series: .value("종류", "온도")
                    )
                    .foregroundStyle(Color.red.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                
                ForEach(correctedSession.graphPoints) { pt in
                    if let ror = pt.ror {
                        LineMark(
                            x: .value("시간", pt.relativeTime),
                            y: .value("RoR", ror * rorScaleFactor + 20.0),
                            series: .value("종류", "RoR")
                        )
                        .foregroundStyle(Color.green.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }

                ForEach(correctedSession.events.filter { !["열량 조절", "예열 시작"].contains($0.type) }) { ev in
                    RuleMark(x: .value("이벤트", ev.elapsedSeconds))
                        .foregroundStyle(eventColor(ev.type).opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top) {
                            Text(shortLabel(ev.type))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(eventColor(ev.type))
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 8)) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let sec = v.as(Double.self) {
                            let absSec = Int(abs(sec))
                            let m = absSec / 60
                            let s = absSec % 60
                            let sign = sec < 0 ? "-" : ""
                            Text(String(format: "%@%02d:%02d", sign, m, s))
                                .font(.system(size: 8))
                        }
                    }
                }
            }
            .chartYAxis {
                // 왼쪽 축: 온도 (0~240°C)
                AxisMarks(position: .leading, values: [0, 40, 80, 120, 160, 200, 240]) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.gray.opacity(0.15))
                    AxisValueLabel {
                        if let t = v.as(Double.self) {
                            Text(String(format: "%.0f°C", t))
                                .font(.system(size: 8))
                                .foregroundColor(.red.opacity(0.8))
                        }
                    }
                }
                
                // 오른쪽 축: RoR (0~rorLimit)
                AxisMarks(position: .trailing, values: rorDisplayTicks) { v in
                    AxisValueLabel {
                        if let displayVal = v.as(Double.self) {
                            let rorVal = (displayVal - 20.0) / rorScaleFactor
                            Text(String(format: "%.0f°C/min", rorVal))
                                .font(.system(size: 8))
                                .foregroundColor(.green.opacity(0.8))
                        }
                    }
                }
            }
            .chartYScale(domain: 0...240)
            .chartXScale(domain: minTime...max(600.0, maxTime))
            .contentShape(Rectangle())
            .onTapGesture {
                if !isForPrinting {
                    isZoomedGraphPresented = true
                }
            }
            .onHover { hovering in
                if !isForPrinting {
                    if hovering {
                        if #available(macOS 15.0, *) {
                            NSCursor.zoomIn.push()
                        } else {
                            NSCursor.pointingHand.push()
                        }
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
    }

    private var eventTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("이벤트 로그")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.gray)

            VStack(spacing: 0) {
                // 헤더행
                HStack {
                    Text("진행시간").frame(width: 55, alignment: .leading)
                    Text("과정시간").frame(width: 55, alignment: .leading)
                    Text("이벤트").frame(width: 90, alignment: .leading)
                    Text("온도").frame(width: 70, alignment: .leading)
                    Text("열량").frame(width: 40, alignment: .leading)
                    Text("설명").frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color(white: 0.93))

                ForEach(Array(correctedSession.events.enumerated()), id: \.element.id) { idx, ev in
                    let times = getEventTimes(for: ev, in: correctedSession.events)
                    HStack {
                        Text(times.total).frame(width: 55, alignment: .leading)
                        Text(times.process).frame(width: 55, alignment: .leading)
                        Text(ev.type).frame(width: 90, alignment: .leading)
                            .foregroundColor(eventColor(ev.type))
                            .fontWeight(.semibold)
                        Text(String(format: "%.1f°C", ev.temperature)).frame(width: 70, alignment: .leading)
                        Text("\(ev.heatValue)").frame(width: 40, alignment: .leading)
                        Text(ev.description).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 10))
                    .foregroundColor(.black)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(idx.isMultiple(of: 2) ? Color.white : Color(white: 0.97))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
            .cornerRadius(6)
        }
    }

    private var memoArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("📝 로스팅 메모")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gray)
                
                if showMemoSavedToast {
                    Text("✓ 저장 완료")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                
                Spacer()
                
                if !isForPrinting {
                    Button(action: {
                        var updated = correctedSession
                        updated.memo = memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : memoText
                        correctedSession = updated
                        RoastSessionStore.shared.save(updated)
                        
                        withAnimation(.easeIn(duration: 0.2)) {
                            showMemoSavedToast = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showMemoSavedToast = false
                            }
                        }
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                            Text("저장")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.appAccent)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if isForPrinting {
                if memoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("작성된 메모가 없습니다.")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(white: 0.97))
                        .cornerRadius(6)
                } else {
                    Text(memoText)
                        .font(.system(size: 11))
                        .foregroundColor(.black)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(white: 0.97))
                        .cornerRadius(6)
                }
            } else {
                TextEditor(text: $memoText)
                    .font(.system(size: 11))
                    .foregroundColor(.black)
                    .frame(height: 70)
                    .padding(6)
                    .background(Color.white)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
        }
    }

    private var reportFooter: some View {
        HStack {
            Text("보카보아(BocaBoa) - 보카보카 250/500BT 커피 로스터 로스팅 프로파일러")
                .font(.system(size: 9))
                .foregroundColor(.gray)
            Spacer()
            Text("creatorjoseph@kakao.com")
                .font(.system(size: 9))
                .foregroundColor(.gray)
        }
    }

    // MARK: - Helpers

    private func getEventTimes(for event: SavedEvent, in events: [SavedEvent]) -> (total: String, process: String) {
        let hasCharge = events.contains(where: { $0.type == "투입" || $0.type == "생두 투입" })
        
        let preheatTime: TimeInterval
        if hasCharge {
            if let startEvent = events.first(where: { $0.type == "예열 시작" }) {
                preheatTime = abs(startEvent.elapsedSeconds)
            } else {
                preheatTime = 0.0
            }
        } else {
            preheatTime = 0.0
        }
        
        let totalSec = hasCharge ? (event.elapsedSeconds + preheatTime) : event.elapsedSeconds
        
        let processSec: TimeInterval
        if hasCharge {
            if event.elapsedSeconds < 0 {
                processSec = event.elapsedSeconds + preheatTime
            } else {
                processSec = event.elapsedSeconds
            }
        } else {
            processSec = event.elapsedSeconds
        }
        
        func format(_ sec: TimeInterval) -> String {
            let absSec = Int(abs(sec))
            let m = absSec / 60
            let s = absSec % 60
            return String(format: "%02d:%02d", m, s)
        }
        
        return (format(totalSec), format(processSec))
    }

    private func formatSec(_ sec: Double) -> String {
        String(format: "%02d:%02d", Int(sec)/60, Int(sec)%60)
    }

    private func eventColor(_ type: String) -> Color {
        switch type {
        case "투입": return .blue
        case "1차 팝": return .orange
        case "2차 팝": return .purple
        case "T.P": return .cyan
        case "종료": return .green
        case "목표 DTR 도달": return .red
        default: return .gray
        }
    }

    private func shortLabel(_ type: String) -> String {
        switch type {
        case "투입": return "투입"
        case "1차 팝": return "1팝"
        case "2차 팝": return "2팝"
        case "T.P": return "T.P"
        case "종료": return "종료"
        default: return type
        }
    }

    // RoR 곡선 보정용 정적 헬퍼 메서드
    private static func recalculateRoR(session: inout RoastSession, windowSize: Double, filterStrength: Double) {
        let chargeTime = session.events.first(where: { $0.type == "생두 투입" || $0.type == "투입" || $0.type.contains("투입") })?.elapsedSeconds ?? 0.0
        var points = session.graphPoints
        
        for i in 0..<points.count {
            let pt = points[i]
            let elapsed = pt.relativeTime
            
            let shouldCalculate = (elapsed - chargeTime >= 60.0)
            
            if shouldCalculate {
                let targetTime = elapsed - windowSize
                if let prevPoint = points[0..<i].first(where: { $0.relativeTime >= targetTime }) {
                    let tempDiff = pt.temperature - prevPoint.temperature
                    let timeDiff = elapsed - prevPoint.relativeTime
                    let minTimeDiff = min(5.0, windowSize / 2.0)
                    if timeDiff > minTimeDiff {
                        let rawRoR = (tempDiff / timeDiff) * 60.0
                        var smoothedRoR = rawRoR
                        
                        var lastRoR: Double? = nil
                        for j in (0..<i).reversed() {
                            if let prevRor = points[j].ror {
                                lastRoR = prevRor
                                break
                            }
                        }
                        
                        if let lastR = lastRoR {
                            let alpha = (100.0 - filterStrength) / 100.0
                            smoothedRoR = (rawRoR * alpha) + (lastR * (1.0 - alpha))
                        }
                        
                        points[i].ror = max(0.0, smoothedRoR)
                    }
                }
            } else {
                points[i].ror = nil
            }
        }
        session.graphPoints = points
    }
}

// MARK: - Print / PDF helpers

extension RoastReportView {

    /// PDF 파일로 저장 (NSSavePanel)
    func savePDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        let safe = correctedSession.beanName.isEmpty ? "unnamed" : correctedSession.beanName.replacingOccurrences(of: " ", with: "_")
        panel.nameFieldStringValue = "\(formatter.string(from: correctedSession.date))_\(safe)_report.pdf"
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            let pdfData = self.renderToPDF(forPrint: true)
            try? pdfData.write(to: url)
        }
    }

    /// 시스템 인쇄 패널 열기
    func printReport() {
        let pdfData = renderToPDF(forPrint: true)
        guard let pdfDoc = PDFDocumentWrapper(data: pdfData) else { return }
        pdfDoc.print()
    }

    /// SwiftUI View → PDF Data
    private func renderToPDF(forPrint: Bool) -> Data {
        let reportToRender = RoastReportView(
            session: correctedSession,
            isForPrinting: forPrint
        )
        let renderer = ImageRenderer(content:
            reportToRender.frame(width: 794)   // A4 포인트 너비 ≈ 794pt
        )
        renderer.scale = 2.0

        let mutableData = NSMutableData()
        renderer.render { size, context in
            var box = CGRect(origin: .zero, size: size)
            guard let consumer = CGDataConsumer(data: mutableData as CFMutableData),
                  let pdfCtx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            pdfCtx.beginPDFPage(nil)
            context(pdfCtx)
            pdfCtx.endPDFPage()
            pdfCtx.closePDF()
        }
        return mutableData as Data
    }
}

// MARK: - Thin NSDocument wrapper for printing

private class PDFDocumentWrapper {
    let data: Data
    init?(data: Data) {
        guard !data.isEmpty else { return nil }
        self.data = data
    }
    func print() {
        guard let tempURL = try? FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: NSTemporaryDirectory()),
            create: true
        ).appendingPathComponent("report_print.pdf") else { return }
        try? data.write(to: tempURL)
        NSWorkspace.shared.open(tempURL)   // Preview가 열리면서 시스템 인쇄 가능
    }
}

// MARK: - Zoomed Graph View for Big Screen Analysis

struct ZoomedGraphView: View {
    let session: RoastSession
    @Binding var correctedSession: RoastSession
    @Binding var rorWindowSize: Double
    @Binding var rorFilterStrength: Double
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // 헤더
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🔍 온도 & RoR 프로파일 확대 분석")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                    Text(correctedSession.beanName.isEmpty ? "이전 기록 분석" : correctedSession.beanName)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                Spacer()
                
                // RoR 보정 슬라이더 패널 (확대 뷰에서도 실시간 제어 연동)
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("윈도우")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Slider(value: $rorWindowSize, in: 5.0...45.0, step: 1.0)
                            .frame(width: 100)
                        Text(String(format: "%.0f초", rorWindowSize))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                    }
                    
                    HStack(spacing: 4) {
                        Text("필터")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                        Slider(value: $rorFilterStrength, in: 0.0...95.0, step: 5.0)
                            .frame(width: 100)
                        Text(String(format: "%.0f%%", rorFilterStrength))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.black)
                    }
                    
                    Button(action: {
                        rorWindowSize = 15.0
                        rorFilterStrength = 90.0
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("RoR 설정 초기화 (시간: 15초, 필터: 90%)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(white: 0.96))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.88), lineWidth: 1))
                
                Spacer().frame(width: 20)
                
                Button("닫기") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .keyboardShortcut(.escape, modifiers: [])
            }
            
            Divider()
            
            // 대형 차트
            ZoomedChartContainer(correctedSession: correctedSession, rorWindowSize: rorWindowSize, rorFilterStrength: rorFilterStrength)
                .frame(height: 330)
        }
        .padding(24)
        .frame(width: 1200, height: 470)
        .background(Color.white)
        .preferredColorScheme(.light)
    }
}

// MARK: - Large Chart Component

struct ZoomedChartContainer: View {
    let correctedSession: RoastSession
    let rorWindowSize: Double
    let rorFilterStrength: Double
    
    var body: some View {
        let minTime = correctedSession.graphPoints.map { $0.relativeTime }.min() ?? 0.0
        let maxTime = correctedSession.graphPoints.map { $0.relativeTime }.max() ?? 0.0

        let maxRoRInData = correctedSession.graphPoints.compactMap { $0.ror }.max() ?? 0.0
        let rawRorLimit = max(25.0, maxRoRInData)
        let rorLimit = ceil(rawRorLimit / 5.0) * 5.0
        let rorScaleFactor = 210.0 / rorLimit
        let rorDisplayTicks = stride(from: 0.0, through: rorLimit, by: 5.0).map { $0 * rorScaleFactor + 20.0 }
        
        Chart {
            // 예열 배경
            if correctedSession.events.first(where: { $0.type == "생두 투입" || $0.type == "투입" || $0.type.contains("투입") }) != nil {
                if minTime < 0 {
                    RectangleMark(
                        xStart: .value("예열시작", minTime),
                        xEnd: .value("예열종료", 0.0),
                        yStart: .value("Y시작", 0.0),
                        yEnd: .value("Y종료", 240.0)
                    )
                    .foregroundStyle(Color.red.opacity(0.04))
                }
            }
            
            // 온도 곡선 (두께 3으로 확대)
            ForEach(correctedSession.graphPoints) { pt in
                LineMark(
                    x: .value("시간", pt.relativeTime),
                    y: .value("온도", pt.temperature),
                    series: .value("종류", "온도")
                )
                .foregroundStyle(Color.red.opacity(0.85))
                .lineStyle(StrokeStyle(lineWidth: 3))
            }
            
            // RoR 곡선 (두께 2.2로 확대)
            ForEach(correctedSession.graphPoints) { pt in
                if let ror = pt.ror {
                    LineMark(
                        x: .value("시간", pt.relativeTime),
                        y: .value("RoR", ror * rorScaleFactor + 20.0),
                        series: .value("종류", "RoR")
                    )
                    .foregroundStyle(Color.green.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 2.2))
                }
            }

            // 이벤트 표식 (어노테이션에 발생 시각 덧붙임)
            ForEach(correctedSession.events.filter { !["열량 조절", "예열 시작"].contains($0.type) }) { ev in
                RuleMark(x: .value("이벤트", ev.elapsedSeconds))
                    .foregroundStyle(eventColor(ev.type).opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [2]))
                    .annotation(position: .top) {
                        VStack(spacing: 2) {
                            Text(shortLabel(ev.type))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(eventColor(ev.type))
                            let absSec = Int(abs(ev.elapsedSeconds))
                            Text(String(format: "%02d:%02d", absSec / 60, absSec % 60))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.gray)
                        }
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 12)) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color(white: 0.9))
                AxisValueLabel {
                    if let sec = v.as(Double.self) {
                        let absSec = Int(abs(sec))
                        let m = absSec / 60
                        let s = absSec % 60
                        let sign = sec < 0 ? "-" : ""
                        Text(String(format: "%@%02d:%02d", sign, m, s))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .chartYAxis {
            // 왼쪽 온도 축
            AxisMarks(position: .leading, values: [0, 40, 80, 120, 160, 200, 240]) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                    .foregroundStyle(Color(white: 0.9))
                AxisValueLabel {
                    if let t = v.as(Double.self) {
                        Text(String(format: "%.0f°C", t))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.red.opacity(0.8))
                    }
                }
            }
            
            // 오른쪽 RoR 축 (1자리 소수점 표기)
            AxisMarks(position: .trailing, values: rorDisplayTicks) { v in
                AxisValueLabel {
                    if let displayVal = v.as(Double.self) {
                        let rorVal = (displayVal - 20.0) / rorScaleFactor
                        Text(String(format: "%.1f°C/min", rorVal))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.green.opacity(0.8))
                    }
                }
            }
        }
        .chartYScale(domain: 0...240)
        .chartXScale(domain: minTime...max(600.0, maxTime))
    }
    
    private func eventColor(_ type: String) -> Color {
        switch type {
        case "투입": return .blue
        case "1차 팝": return .orange
        case "2차 팝": return .purple
        case "T.P": return .cyan
        case "종료": return .green
        case "목표 DTR 도달": return .red
        default: return .gray
        }
    }

    private func shortLabel(_ type: String) -> String {
        switch type {
        case "투입": return "투입"
        case "1차 팝": return "1팝"
        case "2차 팝": return "2팝"
        case "T.P": return "T.P"
        case "종료": return "종료"
        default: return type
        }
    }
}
