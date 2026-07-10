import SwiftUI
import AppKit
import Charts

struct ViewHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ContentView: View {
    @StateObject private var manager = BluetoothManager()
    @EnvironmentObject var nicknameStore: NicknameStore
    
    // 타겟 장비 감지 상태
    @State private var showConnectionRequest = false
    @State private var nicknameInput = ""
    @State private var pendingTargetDevice: BLEDevice? = nil
    
    // 수동 열량 조절 대기 상태
    @State private var pendingHeat: Int = 12
    
    // 그래프 보기 비율 (초 단위)
    enum GraphRangeMode: String, CaseIterable, Identifiable {
        case oneMin = "1분"
        case threeMin = "3분"
        case fiveMin = "5분"
        case tenMin = "10분"
        case all = "전체"
        
        var id: String { self.rawValue }
        
        var seconds: TimeInterval {
            switch self {
            case .oneMin: return 60
            case .threeMin: return 180
            case .fiveMin: return 300
            case .tenMin: return 600
            case .all: return .infinity
            }
        }
    }
    @StateObject private var sessionStore = RoastSessionStore.shared
    @StateObject private var updateChecker = UpdateChecker()

    // 세션 결과 및 브라우저 Sheet
    @State private var showSessionResult = false
    @State private var showSessionBrowser = false
    @State private var showDonation = false
    @State private var showRoRInfo = false
    @State private var showDTRInfo = false
    @State private var rorOffset: CGSize = .zero
    @State private var rorLastOffset: CGSize = .zero
    @State private var dtrOffset: CGSize = .zero
    @State private var dtrLastOffset: CGSize = .zero
    @State private var targetAgtron: Double = 65.0
    
    // 사이드바 영역 동적 세로 길이에 따른 앱 세로 길이 반응용
    @State private var sidebarHeight: CGFloat = 860
    
    // 텍스트 필드 포커스 상태 추적
    @FocusState private var isFieldFocused: Bool
    @State private var selectedRangeMode: GraphRangeMode = .all
    @State private var selectedSessionForDetail: RoastSession? = nil
    @State private var sessionToRename: RoastSession? = nil
    @State private var renameText: String = ""
    
    
    // 목표 DTR 범위별 배전도 가이드
    private var dtrRoastLevelText: String {
        guard let dtr = Double(manager.targetDTR) else { return "" }
        if dtr < 12.0 {
            return "라이트 미만"
        } else if dtr < 15.0 {
            return "라이트(약배전)"
        } else if dtr < 18.0 {
            return "미디엄(중배전)"
        } else if dtr <= 22.0 {
            return "다크(강배전)"
        } else {
            return "다크 초과"
        }
    }
    
    private var recommendedDTRText: String {
        // 로스팅 목적별 기준 범위
        let purposeRange: (Double, Double) = {
            switch manager.roastPurpose {
            case "샘플로스팅":   return (10.0, 14.0)
            case "핸드드립":     return (14.0, 18.0)
            case "에스프레소":   return (18.0, 25.0)
            default:             return (14.0, 18.0)
            }
        }()

        // 가공 방식 오프셋 (+/- 1~2%)
        let methodOffset: (Double, Double) = {
            switch manager.processingMethod {
            case "워시드 (Washed)":              return (0, 0)
            case "내추럴 (Natural)":            return (-2, -2)
            case "펄프드 내추럴 (Pulped Natural)": return (-2, -2)
            case "허니 (Honey)":               return (-1, -1)
            case "무산소발효 (Anaerobic)":       return (-3, -3)
            default:                            return (0, 0)
            }
        }()

        let lo = purposeRange.0 + methodOffset.0
        let hi = purposeRange.1 + methodOffset.1
        return String(format: "권장 %.0f~%.0f%%", lo, hi)
    }
    
    private var dtrRoastLevelColor: Color {
        guard let dtr = Double(manager.targetDTR) else { return .textSecondary }
        if dtr < 12.0 {
            return .gray
        } else if dtr < 15.0 {
            return .orange
        } else if dtr < 18.0 {
            return .brown
        } else {
            return .red
        }
    }

    private var dtrSliderBinding: Binding<Double> {
        Binding(
            get: {
                Double(manager.targetDTR) ?? 15.0
            },
            set: {
                manager.targetDTR = String(format: "%.1f", $0)
            }
        )
    }

    private var currentAgtronValue: Int {
        guard let dtr = Double(manager.targetDTR) else { return 75 }
        let clampedDtr = max(10.0, min(25.0, dtr))
        let ratio = (clampedDtr - 10.0) / 15.0
        return Int(95.0 - (70.0 * ratio))
    }

    private struct AgtronDetail {
        let range: String
        let common: String
        let sca: String
    }
    
    private var currentAgtronDetail: AgtronDetail {
        let val = currentAgtronValue
        if val > 95 {
            return AgtronDetail(range: "150-95", common: "Very Light", sca: "Light")
        } else if val > 85 {
            return AgtronDetail(range: "95-85", common: "Light", sca: "Cinnamon")
        } else if val > 75 {
            return AgtronDetail(range: "85-75", common: "Moderately Light", sca: "Medium")
        } else if val > 65 {
            return AgtronDetail(range: "75-65", common: "Light Medium", sca: "High")
        } else if val > 55 {
            return AgtronDetail(range: "65-55", common: "Medium", sca: "City")
        } else if val > 45 {
            return AgtronDetail(range: "55-45", common: "Moderately Dark", sca: "Full City")
        } else if val > 35 {
            return AgtronDetail(range: "45-35", common: "Dark", sca: "French")
        } else {
            return AgtronDetail(range: "35-25", common: "Very Dark", sca: "Italian")
        }
    }

    // 알림창 상태
    @State private var showAlert = false
    @State private var alertMessage = ""

    private func clearFocus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let window = NSApp.keyWindow {
                if !window.makeFirstResponder(nil) {
                    window.makeFirstResponder(window.contentView)
                }
            }
        }
    }

    var body: some View {
        ZStack {
            HStack(alignment: .top, spacing: 0) {
                // 1. 왼쪽 제어 및 설정 사이드바
                sidebarView
                    .frame(width: 320)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Color.appSurface2)
                    .overlay(Rectangle().fill(Color.appBorder).frame(width: 1), alignment: .trailing)
                
                // 2. 오른쪽 모니터링 및 실시간 그래프
                mainDashboardView
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(Color.appBackground)
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("로스팅 알림"), message: Text(alertMessage), dismissButton: .default(Text("확인")))
            }
            
            if showRoRInfo {
                RoRInfoView(isPresented: $showRoRInfo)
                    .offset(rorOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                rorOffset = CGSize(
                                    width: rorLastOffset.width + value.translation.width,
                                    height: rorLastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { value in
                                rorLastOffset = rorOffset
                            }
                    )
                    .zIndex(9999)
            }
            
            if showDTRInfo {
                DTRInfoView(isPresented: $showDTRInfo)
                    .offset(dtrOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                dtrOffset = CGSize(
                                    width: dtrLastOffset.width + value.translation.width,
                                    height: dtrLastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { value in
                                dtrLastOffset = dtrOffset
                            }
                    )
                    .zIndex(9999)
            }
        }
        .ignoresSafeArea()
        .background(Color.appBackground)
        .preferredColorScheme(.light)
        .frame(minWidth: 1300, maxWidth: .infinity, minHeight: sidebarHeight, maxHeight: .infinity)
        .onTapGesture {
            clearFocus()
        }
        .onPreferenceChange(ViewHeightKey.self) { newHeight in
            // 사이드바 실제 콘텐츠의 높이에 하단 마진을 더한 크기로 반응 (최소 860)
            let adjustedHeight = newHeight + 20
            if adjustedHeight != sidebarHeight {
                sidebarHeight = max(860, adjustedHeight)
            }
        }
        .onChange(of: manager.activeAlertMessage) { newMessage in
            if let msg = newMessage {
                alertMessage = msg
                showAlert = true
                // 메세지 해제 처리
                manager.activeAlertMessage = nil
            }
        }
        .onChange(of: manager.rorWindowSize) { _ in
            if let guide = manager.guideSession {
                manager.setGuideSession(guide)
            }
        }
        .onChange(of: manager.rorFilterStrength) { _ in
            if let guide = manager.guideSession {
                manager.setGuideSession(guide)
            }
        }
        .onAppear {
            updateChecker.checkForUpdates()
            // 앱 실행 시 첫 번째 텍스트 필드가 자동 포커싱되어 단축키 입력이 차단되는 문제 방지
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                clearFocus()
            }
        }
        .alert(isPresented: $updateChecker.isUpdateAvailable) {
            Alert(
                title: Text("새로운 업데이트 가능!"),
                message: Text("보카보아 앱의 새로운 버전(v\(updateChecker.latestVersion))이 출시되었습니다. 업데이트하시겠습니까?"),
                primaryButton: .default(Text("다운로드 가기")) {
                    if let url = updateChecker.releaseUrl {
                        NSWorkspace.shared.open(url)
                    }
                },
                secondaryButton: .cancel(Text("나중에"))
            )
        }
        .sheet(isPresented: $showDonation) {
            VStack(spacing: 24) {
                Text("개발자 후원 안내")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("보카보아 앱이 도움이 되셨다면 개발자에게 커피 한 잔만 사 주세요.\n후원금은 앱 유지보수 및 기능 개선에 사용됩니다.")
                    .font(.system(size: 13))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 30) {
                    if let kakao = NSImage(named: "kakaobank.png") {
                        Text("카카오뱅크")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.textPrimary)    

                        Image(nsImage: kakao)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 200)

                    } else {
                        Text("카카오뱅크")
                    }
                    
                    if let paypal = NSImage(named: "paypal.png") {
                        Text("PayPal")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.textPrimary)
                            
                        Image(nsImage: paypal)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 200)

                    } else {
                        Text("PayPal")
                    }
                }
                
                Button("닫기") {
                    showDonation = false
                }
                .buttonStyle(.bordered)
            }
            .padding(40)
            .background(Color.appSurface)
        }
        .onChange(of: manager.targetDeviceDiscovered?.id) { newId in
            if let device = manager.targetDeviceDiscovered {
                self.pendingTargetDevice = device
                self.nicknameInput = nicknameStore.nickname(for: device.peripheralUUID) ?? ""
                self.showConnectionRequest = true
            }
        }
        .sheet(isPresented: $showConnectionRequest) {
            VStack(spacing: 18) {
                Text("보카보카 블루투스기기 감지됨")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
                
                Text("'PRL-SPP-03' 기기가 감지되었습니다.\n연결하여 사용기기로 등록할까요?")
                    .font(.system(size: 12))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("장비 별명 (선택)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textSecondary)
                    TextField("예: 우리집 로스터기", text: $nicknameInput)
                        .textFieldStyle(CustomFocusRingTextFieldStyle())
                        .frame(width: 250)
                }
                .padding(.vertical, 4)
                
                HStack(spacing: 12) {
                    Button("취소") {
                        manager.targetDeviceDiscovered = nil
                        showConnectionRequest = false
                    }
                    .buttonStyle(.bordered)
                    
                    Button("연결 및 등록") {
                        if let device = pendingTargetDevice {
                            nicknameStore.setNickname(nicknameInput, for: device.peripheralUUID)
                            manager.connect(device)
                        }
                        manager.targetDeviceDiscovered = nil
                        showConnectionRequest = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                }
            }
            .padding(20)
            .frame(width: 300)
            .background(Color.appSurface)
            .preferredColorScheme(.light)
        }
        .frame(minWidth: 1000, minHeight: 700)
        .background(Color.appBackground)
        .preferredColorScheme(.light)
        .onAppear {
            pendingHeat = manager.currentHeat
        }
        .onChange(of: manager.currentHeat) { newHeat in
            pendingHeat = newHeat
        }
        .onChange(of: manager.completedSession?.id) { _ in
            if manager.completedSession != nil {
                showSessionResult = true
            }
        }
        // ── 로스팅 종료 결과 Sheet ──────────────────────────
        .sheet(isPresented: $showSessionResult) {
            if let session = manager.completedSession {
                SessionResultSheet(
                    session: session,
                    sessionStore: sessionStore,
                    onSetGuide: { manager.setGuideSession($0) }
                )
            }
        }
        // ── 기록 브라우저 Sheet ────────────────────────────
        .sheet(isPresented: $showSessionBrowser) {
            SessionBrowserSheet(
                sessionStore: sessionStore,
                onLoadGuide: { session in
                    manager.setGuideSession(session)
                    showSessionBrowser = false
                }
            )
        }
        .sheet(item: $selectedSessionForDetail) { session in
            VStack(spacing: 0) {
                HStack {
                    Text("기록 상세 정보")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button {
                        manager.setGuideSession(session)
                        selectedSessionForDetail = nil
                    } label: {
                        Label("이 기록을 가이드로 설정", systemImage: "map.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    
                    Button {
                        RoastReportView(session: session).savePDF()
                    } label: {
                        Label("PDF 저장", systemImage: "arrow.down.doc.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.appAccent)
                    
                    Button {
                        RoastSessionStore.shared.saveWithPanel(session)
                    } label: {
                        Label("기록 내보내기", systemImage: "square.and.arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.appAccent)
                    
                    Button {
                        RoastReportView(session: session).printReport()
                    } label: {
                        Label("인쇄", systemImage: "printer.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.appAccent)
                    
                    Button {
                        selectedSessionForDetail = nil
                    } label: {
                        Text("닫기").font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(Color.appSurface2)
                
                Divider()
                
                ScrollView {
                    RoastReportView(session: session)
                        .frame(width: 700)
                        .padding(20)
                }
                .background(Color.white)
            }
            .frame(width: 760, height: 700)
            .preferredColorScheme(.light)
        }
        .alert("이름 변경", isPresented: Binding(
            get: { sessionToRename != nil },
            set: { if !$0 { sessionToRename = nil } }
        )) {
            TextField("원두 이름", text: $renameText)
            Button("확인") {
                if let session = sessionToRename, !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                    sessionStore.rename(session, newName: renameText.trimmingCharacters(in: .whitespaces))
                }
                sessionToRename = nil
            }
            Button("취소", role: .cancel) { sessionToRename = nil }
        } message: {
            Text("새로운 원두 이름을 입력하세요.")
        }
    }

    // MARK: - Sidebar View (Left)
    
        @ViewBuilder
    private var sidebarView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
            // 앱 로고 및 이름 헤더
            HStack(spacing: 5) {
                let iconImage = NSImage(named: "NSApplicationIcon") ?? NSImage(named: "AppIcon")
                if let appIcon = iconImage {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 62, height: 62)
                } else {
                    Image(systemName: "flame.circle.fill")
                        .resizable()
                        .foregroundColor(.appWarning)
                        .frame(width: 62, height: 62)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    if let nameImage = NSImage(named: "appname.png") {
                        Image(nsImage: nameImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 32)
                    } else {
                        Text("보카보아")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.textPrimary)
                    }
                    Text("보카보카250/500BT 커피로스터 프로파일러")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 36)
            
            
                VStack(spacing: 14) {
                    // ── 가이드 모드 배너 ────────────────────────────
                    if let guide = manager.guideSession {
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "map.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.appAccent)
                                Text("가이드 모드")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.appAccent)
                                Spacer()
                                Button {
                                    manager.setGuideSession(nil)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(.textTertiary)
                                }
                                .buttonStyle(.plain)
                                .help("가이드 해제")
                            }
                            HStack {
                                Text(guide.beanName.isEmpty ? "unnamed" : guide.beanName)
                                    .font(.system(size: 10))
                                    .foregroundColor(.textSecondary)
                                Text("·")
                                    .foregroundColor(.textTertiary)
                                Text(guide.displayDate)
                                    .font(.system(size: 10))
                                    .foregroundColor(.textTertiary)
                                Spacer()
                                if let next = manager.nextGuideEvent {
                                    Text("다음: \(next.type)")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.appAccent.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appAccent.opacity(0.3), lineWidth: 1))
                        .cornerRadius(8)
                        .padding(.horizontal, 16)
                    }
                    
                    // Divider().padding(.horizontal, 16)
                    
                    // 로스팅 세션 입력 폼
                    VStack(spacing: 10) {
                        
                        HStack(spacing: 8) {
                            Text("커피 품종")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .frame(width: 60, alignment: .leading)
                            TextField("예: Ethiopia Yirgacheffe G1", text: $manager.beanName)
                                .textFieldStyle(CustomFocusRingTextFieldStyle())
                                .focused($isFieldFocused)
                                .onSubmit {
                                    clearFocus()
                                }
                        }
                        
                        HStack(spacing: 8) {
                            Text("가공 방식")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .frame(width: 60, alignment: .leading)
                            let methods = ["워시드 (Washed)", "내추럴 (Natural)", "허니 (Honey)", "무산소 (Anaerobic)", "디카페인 (Decaf)", "기타"]
                            Picker("", selection: $manager.processingMethod) {
                                ForEach(methods, id: \.self) { method in
                                    Text(method).tag(method)
                                }
                            }
                            .labelsHidden()
                            Spacer()
                        }
                        
                        HStack(spacing: 8) {
                            Text("로스팅 목적")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textSecondary)
                                .frame(width: 60, alignment: .leading)
                            let purposes = ["샘플로스팅", "핸드드립", "에스프레소"]
                            Picker("", selection: $manager.roastPurpose) {
                                ForEach(purposes, id: \.self) { purpose in
                                    Text(purpose).tag(purpose)
                                }
                            }
                            .labelsHidden()
                            Spacer()
                        }
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("투입 용량 (g)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                TextField("160", text: $manager.beanWeight)
                                    .font(.system(size: 14, weight: .medium))
                                    .textFieldStyle(CustomFocusRingTextFieldStyle())
                                    .focused($isFieldFocused)
                                    .onSubmit {
                                        clearFocus()
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("예열 온도 (°C)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                TextField("220", text: $manager.preheatTemp)
                                    .font(.system(size: 14, weight: .medium))
                                    .textFieldStyle(CustomFocusRingTextFieldStyle())
                                    .focused($isFieldFocused)
                                    .onSubmit {
                                        clearFocus()
                                    }
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("목표 DTR %")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.textSecondary)
                                Spacer()
                                Text(recommendedDTRText)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.appAccent)
                            }
                            
                            HStack(spacing: 8) {
                                Slider(value: dtrSliderBinding, in: 10.0...25.0)
                                
                                TextField("15.0", text: $manager.targetDTR)
                                    .textFieldStyle(CustomFocusRingTextFieldStyle())
                                    .frame(width: 60)
                                    .font(.system(size: 14, weight: .medium))
                                    .multilineTextAlignment(.center)
                                    .focused($isFieldFocused)
                                    .onSubmit {
                                        clearFocus()
                                    }
                            }
                        }
                        
                        // 아그트론 그라데이션 바
                        let agtronColors = [
                            Color(hex: "#CE8101"), // 95
                            Color(hex: "#C47C04"), // 85
                            Color(hex: "#B46B0C"), // 75
                            Color(hex: "#995515"), // 65
                            Color(hex: "#8B4B1B"), // 55
                            Color(hex: "#7A4719"), // 45
                            Color(hex: "#673F1C"), // 35
                            Color(hex: "#532C1B")  // 25
                        ]
                        
                        VStack(spacing: 2) {
                            HStack {
                                Text("Agtron: #\(currentAgtronValue)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.appAccent)
                                Spacer()
                            }
                            
                            GeometryReader { geo in
                                let dtrVal = Double(manager.targetDTR) ?? 15.0
                                let clampedDtr = max(10.0, min(25.0, dtrVal))
                                let percent = (clampedDtr - 10.0) / 15.0
                                let indicatorWidth: CGFloat = 8.0
                                let safeWidth = geo.size.width - indicatorWidth
                                let indicatorX = (safeWidth * CGFloat(percent)) + (indicatorWidth / 2)
                                
                                ZStack(alignment: .topLeading) {
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(LinearGradient(colors: agtronColors, startPoint: .leading, endPoint: .trailing))
                                        .frame(height: 14)
                                    
                                    Image(systemName: "triangle.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.appAccent)
                                        .position(x: indicatorX, y: 18)
                                }
                            }
                            .frame(height: 22)
                        }
                        // .padding(.top, 0)
                        
                        // 1행 3열 Agtron 상세 정보 테이블
                        HStack(spacing: 0) {
                            let detail = currentAgtronDetail
                            
                            VStack(spacing: 0) {
                                Text("수치 범위")
                                    .font(.system(size: 11))
                                    .foregroundColor(.textSecondary)
                                Text(detail.range)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            
                            Divider().frame(height: 18)
                            
                            VStack(spacing: 2) {
                                Text("일반 분류")
                                    .font(.system(size: 11))
                                    .foregroundColor(.textSecondary)
                                Text(detail.common)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                            
                            Divider().frame(height: 18)
                            
                            VStack(spacing: 2) {
                                Text("SCA 분류")
                                    .font(.system(size: 11))
                                    .foregroundColor(.textSecondary)
                                Text(detail.sca)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.textPrimary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 6)
                        .background(Color.appSurface2)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.appBorder, lineWidth: 1)
                        )
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 16)

                    // 수동 열량 조절 (0~12)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("수동 열량 조절 (0~12)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.textSecondary)
                            Spacer()
                            Text("(- / =)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.textTertiary)
                            Text("\(pendingHeat)")
                                .font(.system(size:14, weight: .bold, design: .monospaced))
                                .foregroundColor(.textPrimary)
                        }
                        
                        HStack {
                            Slider(value: Binding(
                                get: { Double(pendingHeat) },
                                set: { pendingHeat = Int($0) }
                            ), in: 0...12, step: 1.0)
                            
                            Stepper("", value: Binding(
                                get: { pendingHeat },
                                set: { pendingHeat = $0 }
                            ), in: 0...12)
                            .labelsHidden()
                        }
                        
                        Button {
                            manager.adjustHeat(to: pendingHeat)
                        } label: {
                            HStack {
                                Text("열량 변경 확인")
                                Spacer()
                                Text("Enter")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.2))
                                    .cornerRadius(3)
                            }
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.gray)

                        Group {
                            // 1. 감소 단축키 (- 키) - 대기값만 감소
                            Button {
                                pendingHeat = max(0, pendingHeat - 1)
                            } label: { EmptyView() }
                            .keyboardShortcut("-", modifiers: [])
                            .disabled(isFieldFocused)
                            
                            // 2. 증가 단축키 (= 키) - 대기값만 증가
                            Button {
                                pendingHeat = min(12, pendingHeat + 1)
                            } label: { EmptyView() }
                            .keyboardShortcut("=", modifiers: [])
                            .disabled(isFieldFocused)

                            // 3. 감소 단축키 (아래 방향키) - 대기값만 감소
                            Button {
                                pendingHeat = max(0, pendingHeat - 1)
                            } label: { EmptyView() }
                            .keyboardShortcut(.downArrow, modifiers: [])
                            .disabled(isFieldFocused)

                            // 4. 증가 단축키 (위 방향키) - 대기값만 증가
                            Button {
                                pendingHeat = min(12, pendingHeat + 1)
                            } label: { EmptyView() }
                            .keyboardShortcut(.upArrow, modifiers: [])
                            .disabled(isFieldFocused)
                            
                            // 5. 텍스트 직접 입력 후 Enter 키 적용
                            Button {
                                manager.adjustHeat(to: pendingHeat)
                            } label: { EmptyView() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(isFieldFocused)
                        }
                        .frame(width: 0, height: 0)
                        .opacity(0)
                    }
                    .padding(8)
                    .background(Color.appSurface)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.appBorder, lineWidth: 1))
                    .padding(.horizontal, 16)

                    // 액션 버튼 그룹 (2x2)
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Button {
                                manager.startPreheating()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "flame.fill")
                                    Text("예열 시작")
                                    Spacer()
                                    Text("R")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .disabled(manager.roastState != .idle && manager.roastState != .completed)
                            .keyboardShortcut("r", modifiers: [])

                            Button {
                                manager.chargeBeans()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "tray.and.arrow.down.fill")
                                    Text("생두 투입")
                                    Spacer()
                                    Text("S")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.appAccent)
                            .disabled(manager.roastState != .preheating)
                            .keyboardShortcut("s", modifiers: [])
                        }
                        
                        HStack(spacing: 8) {
                            Button {
                                manager.triggerFirstPop()
                            } label: {
                                HStack(spacing: 4) {
                                    Text("1차 팝")
                                    Spacer()
                                    Text("1")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .foregroundColor(manager.roastState == .roasting ? .white : .textTertiary)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(manager.roastState == .roasting ? .pink : Color.appSurface)
                            .disabled(manager.roastState != .roasting)
                            .keyboardShortcut("1", modifiers: [])
                            
                            Button {
                                manager.triggerSecondPop()
                            } label: {
                                HStack(spacing: 4) {
                                    Text("2차 팝")
                                    Spacer()
                                    Text("2")
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .foregroundColor(manager.roastState == .firstPop ? .white : .textTertiary)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(manager.roastState == .firstPop ? .pink : Color.appSurface)
                            .disabled(manager.roastState != .firstPop)
                            .keyboardShortcut("2", modifiers: [])
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // 예상 종료 시각 카드 (항상 표시)
                    Group {
                        if let endTime = manager.estimatedEndTime,
                           manager.roastState == .firstPop || manager.roastState == .secondPop {
                            let devSec = manager.estimatedDevSeconds
                            let remaining = max(0, endTime.timeIntervalSinceNow)
                            let isOverdue = endTime.timeIntervalSinceNow < 0
                            
                            VStack(spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "timer")
                                        .font(.system(size: 11))
                                        .foregroundColor(isOverdue ? .appError : .orange)
                                    Text(isOverdue ? "목표 시간 초과" : "예상 종료까지")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(isOverdue ? .appError : .orange)
                                    Spacer()
                                    Text(endTime, style: .time)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.textTertiary)
                                }
                                
                                HStack(spacing: 0) {
                                    // 카운트다운
                                    Text(isOverdue ? "+\(formatTimeInterval(abs(endTime.timeIntervalSinceNow)))" : formatTimeInterval(remaining))
                                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                                        .foregroundColor(isOverdue ? .appError : .orange)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("목표 DTR \(String(format: "%.1f", Double(manager.targetDTR) ?? 0))%")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.textTertiary)
                                        let m = Int(devSec) / 60
                                        let s = Int(devSec) % 60
                                        Text(String(format: "Develop Time %02d:%02d", m, s))
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(.textTertiary)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isOverdue ? Color.appError.opacity(0.08) : Color.orange.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isOverdue ? Color.appError.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                            )
                        } else {
                            // 1차 팝 이전 대기 상태
                            VStack(spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 11))
                                        .foregroundColor(.textTertiary)
                                    Text("예상 종료까지")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.textTertiary)
                                    Spacer()
                                    Text("--:--")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.textTertiary)
                                }
                                
                                HStack(spacing: 0) {
                                    Text("--:--")
                                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                                        .foregroundColor(.textTertiary)
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("목표 DTR \(String(format: "%.1f", Double(manager.targetDTR) ?? 0))%")
                                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.textTertiary)
                                        Text("1차 팝 이후 계산됨")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.textTertiary)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.appSurface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 16)

                    // 종료
                    Button {
                        manager.finishRoasting()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.circle.fill")
                            Text("종료 및 배출")
                            Spacer()
                            Text("E")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appSuccess)
                    .disabled(manager.roastState == .idle || manager.roastState == .completed)
                    .keyboardShortcut("e", modifiers: [])
                    .padding(.horizontal, 16)

                    HStack(spacing: 8) {
    // 다시 시작
    Button {
        manager.restartRoasting()
    } label: {
        HStack {
            Image(systemName: "arrow.counterclockwise")
            Text("다시 시작")
        }
        .font(.system(size: 12, weight: .bold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
    .buttonStyle(.bordered)
    .tint(.appWarning)
    .disabled(!(manager.roastState == .preheating || manager.roastState == .roasting))

    // 로스팅 취소
    Button {
        manager.cancelRoasting()
    } label: {
        HStack {
            Image(systemName: "xmark.circle")
            Text("로스팅 취소")
        }
        .font(.system(size: 12, weight: .bold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
    .buttonStyle(.bordered)
    .tint(.appError)
    .disabled(!(manager.roastState == .preheating || manager.roastState == .roasting || manager.roastState == .completed))
}
.padding(.horizontal, 16)
                }
            }
            .background(GeometryReader { geo in
                Color.clear.preference(key: ViewHeightKey.self, value: geo.size.height)
            })
            
            Spacer()
        } // Outer VStack
        .frame(width: 320)
        .background(Color.appSurface2)
    }

    // MARK: - Main Dashboard View (Right)
    
    private var mainDashboardView: some View {
        VStack(spacing: 12) {
            // 상단 연결 및 컨트롤 바
            HStack(alignment: .center) {
                Spacer()
                headerConnectionView
            }
            .padding(.horizontal, 15)
            .padding(.top, 12)
            
            // 상단 실시간 메트릭 모니터
            HStack(spacing: 16) {
                metricCard(
                    title: "현재 온도",
                    value: manager.temperatureHistory.first.map { String(format: "%.1f°C", $0.celsius) } ?? "--.-°C",
                    icon: "thermometer",
                    color: .appError
                )
                
                metricCard(
                    title: "예열 시간",
                    value: formatTimeInterval(manager.preheatDuration),
                    icon: "flame.fill",
                    color: .orange
                )
                
                metricCard(
                    title: "로스팅 시간",
                    value: formatTimeInterval(manager.roastDuration),
                    icon: "timer",
                    color: .appAccent
                )
                
                metricCard(
                    title: "RoR (Rate of Rise)",
                    value: String(format: "%+.1f°C/min", manager.currentRoR),
                    icon: "chart.line.uptrend.xyaxis",
                    color: manager.currentRoR >= 0 ? .appError : .appAccent,
                    infoAction: { showRoRInfo = true }
                )
                
                metricCard(
                    title: "DTR (Development Time Ratio)",
                    value: String(format: "%.1f%%", manager.currentDTR),
                    icon: "percent",
                    color: .appWarning,
                    infoAction: { showDTRInfo = true }
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            
            // 진행 상태 바
            HStack(spacing: 12) {
                Text("진행 상태:")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.textSecondary)
                Text(manager.roastState.rawValue)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stateColor(manager.roastState))
                    .cornerRadius(6)
                
                if let tpTemp = manager.turningPointTemp, let tpTime = manager.turningPointTime {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path.ecg")
                        Text("T.P:")
                            .fontWeight(.bold)
                        Text(String(format: "%.1f°C", tpTemp))
                        Text("(\(formatDateToElapsed(tpTime)))")
                            .foregroundColor(.textSecondary)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.appDiscovered.opacity(0.1))
                    .foregroundColor(.appDiscovered)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appDiscovered.opacity(0.3), lineWidth: 1))
                }
                
                Spacer()
                
                // ROR 그래프 설정 (한 줄 수평 배치)
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 11))
                            .foregroundColor(.appAccent)
                        Text("RoR 설정")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.appAccent)
                    }
                    
                    // 측정 시간 조절기
                    HStack(spacing: 6) {
                        Text("측정 시간")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                        Slider(value: $manager.rorWindowSize, in: 5.0...45.0, step: 1.0)
                            .frame(width: 100)
                        Text(String(format: "%.0f초", manager.rorWindowSize))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.textPrimary)
                            .frame(width: 35, alignment: .trailing)
                    }
                    
                    // 필터 강도 조절기
                    HStack(spacing: 6) {
                        Text("필터 강도")
                            .font(.system(size: 11))
                            .foregroundColor(.textSecondary)
                        Slider(value: $manager.rorFilterStrength, in: 0.0...95.0, step: 5.0)
                            .frame(width: 100)
                        Text(String(format: "%.0f%%", manager.rorFilterStrength))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.textPrimary)
                            .frame(width: 35, alignment: .trailing)
                    }
                    
                    // 초기화 버튼 (새로고침 아이콘)
                    Button(action: {
                        manager.rorWindowSize = 15.0
                        manager.rorFilterStrength = 90.0
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.appAccent)
                    }
                    .buttonStyle(.plain)
                    .help("RoR 설정 초기화 (시간: 15초, 필터: 90%)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.appSurface)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.appBorder, lineWidth: 1))
            }
            .padding(.horizontal, 20)
            
            // 중단 실시간 그래프 패널
            VStack(spacing: 8) {
                HStack {
                    // 범례 정보
                    HStack(spacing: 12) {
                        legendItem(color: .gray, label: "예열 시작", style: .dash)
                        legendItem(color: .yellow, label: "열량 조절", style: .dash)
                        legendItem(color: .blue, label: "생두 투입", style: .solid)
                        legendItem(color: .purple, label: "T.P (터닝 포인트)", style: .solid)
                        legendItem(color: .orange, label: "1차 팝핑", style: .solid)
                        legendItem(color: .pink, label: "2차 팝핑", style: .solid)
                        legendItem(color: .red, label: "목표 DTR (중지)", style: .solid)
                        legendItem(color: .green, label: "종료 및 배출", style: .solid)
                    }
                    Spacer()
                    
                    // 그래프 비율 조절 피커
                    Picker("그래프 범위", selection: $selectedRangeMode) {
                        ForEach(GraphRangeMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 250)
                }
                .padding(.horizontal, 8)
                
                // 그래프 캔버스
                chartCanvasView
                    .frame(height: 400)
                    .padding(14)
                    .background(Color.appSurface)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.appBorder, lineWidth: 1))
            }
            .padding(.horizontal, 20)
            
            // 하단 2단 레이아웃 (1열: 이전기록 목록, 2열: 실시간 및 이전 기록 로그)
            HStack(alignment: .top, spacing: 16) {
                // 1열: 이전 기록 목록
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("이전 기록 목록")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.textSecondary)
                        Spacer()
                        
                        Button(action: {
                            sessionStore.importSessionStore { success, beanName in
                                if success, let name = beanName {
                                    print("성공적으로 \(name) 프로파일을 가져왔습니다.")
                                }
                            }
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 9, weight: .bold))
                                Text("가져오기")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.appAccent)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    ScrollView {
                        VStack(spacing: 6) {
                            if sessionStore.sessions.isEmpty {
                                Text("저장된 기록이 없습니다.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.textTertiary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 20)
                            } else {
                                ForEach(sessionStore.sessions) { session in
                                    Button {
                                        selectedSessionForDetail = session
                                    } label: {
                                        HStack(spacing: 6) {
                                            // 연필 아이콘 (이름 변경) - 커스텀 SVG
                                            Button {
                                                renameText = session.beanName
                                                sessionToRename = session
                                            } label: {
                                                let pencilImage = NSImage(contentsOfFile: Bundle.main.path(forResource: "pencil", ofType: "svg") ?? "")
                                                Group {
                                                    if let img = pencilImage {
                                                        Image(nsImage: img)
                                                            .resizable()
                                                            .scaledToFit()
                                                            .frame(width: 12, height: 12)
                                                    } else {
                                                        Image(systemName: "pencil")
                                                            .font(.system(size: 10))
                                                    }
                                                }
                                                .foregroundColor(.textTertiary)
                                                .padding(4)
                                                .background(Color.appSurface)
                                                .cornerRadius(4)
                                            }
                                            .buttonStyle(.plain)
                                            
                                            Text(session.beanName.isEmpty ? "unnamed" : session.beanName)
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.textPrimary)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(session.displayDate)
                                                .font(.system(size: 9))
                                                .foregroundColor(.textTertiary)
                                            if manager.guideSession?.id == session.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.appAccent)
                                            }
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(manager.guideSession?.id == session.id ? Color.appAccent.opacity(0.1) : Color.appBackground)
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(manager.guideSession?.id == session.id ? Color.appAccent.opacity(0.3) : Color.appBorder, lineWidth: 1)
                                        )
                                    }
                                     .buttonStyle(.plain)
                                     .contextMenu {
                                         Button {
                                             renameText = session.beanName
                                             sessionToRename = session
                                         } label: {
                                             let pencilImage: NSImage? = {
                                                 guard let path = Bundle.main.path(forResource: "pencil", ofType: "svg"),
                                                       let img = NSImage(contentsOfFile: path) else { return nil }
                                                 let resized = NSImage(size: NSSize(width: 16, height: 16))
                                                 resized.lockFocus()
                                                 img.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
                                                 resized.unlockFocus()
                                                 return resized
                                             }()
                                             Label {
                                                 Text("이름 변경")
                                             } icon: {
                                                 if let img = pencilImage {
                                                     Image(nsImage: img)
                                                 } else {
                                                     Image(systemName: "pencil")
                                                         .font(.system(size: 12))
                                                 }
                                             }
                                         }
                                     }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
                
                // 2열: 로그 보여주기
                VStack(alignment: .leading, spacing: 8) {
                    let isIdleWithGuide = manager.roastState == .idle && manager.guideSession != nil
                    Text(isIdleWithGuide ? "이전 기록 로그" : "세션 실시간 로그")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.textSecondary)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if isIdleWithGuide {
                                let events = manager.guideSession?.events ?? []
                                if events.isEmpty {
                                    Text("로그 기록이 없습니다.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textTertiary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 20)
                                } else {
                                    ForEach(events.reversed()) { event in
                                        HStack(spacing: 8) {
                                            Text("[\(formattedTimes(for: event, in: events))]")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundColor(.textSecondary)
                                            Text(event.type)
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(eventTypeColor(event.type))
                                                .cornerRadius(4)
                                            Text(event.description)
                                                .font(.system(size: 12))
                                                .foregroundColor(.textPrimary)
                                            Spacer()
                                            Text(String(format: "%.1f°C", event.temperature))
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .foregroundColor(.textSecondary)
                                        }
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .background(Color.appBackground)
                                        .cornerRadius(6)
                                    }
                                }
                            } else {
                                if manager.roastEvents.isEmpty {
                                    Text("진행 중인 로그가 없습니다. 예열 시작 버튼을 누르면 기록이 시작됩니다.")
                                        .font(.system(size: 12))
                                        .foregroundColor(.textTertiary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, 20)
                                } else {
                                    ForEach(manager.roastEvents.reversed()) { event in
                                         HStack(spacing: 8) {
                                             Text("[\(formattedTimes(for: event, in: manager.roastEvents))]")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundColor(.textSecondary)
                                            
                                            Text(event.type)
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(eventTypeColor(event.type))
                                                .cornerRadius(4)
                                            
                                            Text(event.description)
                                                .font(.system(size: 12))
                                                .foregroundColor(.textPrimary)
                                            
                                            Spacer()
                                            
                                            Text(String(format: "%.1f°C", event.temperature))
                                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                                .foregroundColor(.textSecondary)
                                        }
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 8)
                                        .background(Color.appBackground)
                                        .cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 20)
                
            HStack(spacing: 8) {
                Spacer()
                Text("Copyright &copy; 2026~ 크리에이터 요셉(creatorjoseph@kakao.com)")
                    .font(.system(size: 11))
                    .foregroundColor(.textTertiary)
                
                if let sponImage = NSImage(named: "spon.png") {
                    Button(action: {
                        showDonation = true
                    }) {
                        Image(nsImage: sponImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 30)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Metric Card Component
    
    private func metricCard(title: String, value: String, icon: String, color: Color, infoAction: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textSecondary)
                
                if let infoAction = infoAction {
                    Button(action: infoAction) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 2)
                }
            }
            
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.appSurface)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.appBorder, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.02), radius: 3, x: 0, y: 1)
    }
    
    // MARK: - Event formatted time calculations (total elapsed vs. process elapsed)
    
    private func formattedTimes(for event: BluetoothManager.RoastEvent, in events: [BluetoothManager.RoastEvent]) -> String {
        let hasCharge = events.contains(where: { $0.type == "투입" || $0.type == "생두 투입" })
        
        let preheatTime: TimeInterval
        if hasCharge {
            if let startEvent = events.first(where: { $0.type == "예열 시작" }) {
                preheatTime = abs(startEvent.elapsedSeconds)
            } else {
                preheatTime = 0.0
            }
        } else {
            preheatTime = manager.elapsedSeconds
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
        
        return "\(format(totalSec))  \(format(processSec))"
    }

    private func formattedTimes(for event: SavedEvent, in events: [SavedEvent]) -> String {
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
        
        return "\(format(totalSec))  \(format(processSec))"
    }

    // MARK: - Legend Item Component
    
    enum LegendLineStyle {
        case solid, dash
    }
    
    private func legendItem(color: Color, label: String, style: LegendLineStyle) -> some View {
        HStack(spacing: 4) {
            if style == .solid {
                Rectangle()
                    .fill(color)
                    .frame(width: 14, height: 3)
            } else {
                HStack(spacing: 2) {
                    ForEach(0..<3) { _ in
                        Rectangle().fill(color).frame(width: 3, height: 3)
                    }
                }
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.textSecondary)
        }
    }
    
    // MARK: - Real-time Chart Canvas View
    
    private var chartCanvasView: some View {
        let guideMin = manager.guideSession?.graphPoints.map { $0.relativeTime }.min() ?? 0.0
        let liveMin = manager.roastGraphData.map { $0.relativeTime }.min() ?? 0.0
        let totalMin = min(0.0, min(guideMin, liveMin))
        
        let guideMax = manager.guideSession?.graphPoints.map { $0.relativeTime }.max() ?? 0.0
        let liveMax = manager.roastGraphData.map { $0.relativeTime }.max() ?? 0.0
        let totalMax = max(600.0, max(guideMax, liveMax))
        
        let minTime: Double
        let maxTime: Double
        
        if manager.guideSession != nil || selectedRangeMode == .all {
            minTime = totalMin
            maxTime = totalMax
        } else {
            minTime = max(totalMin, manager.elapsedSeconds - selectedRangeMode.seconds)
            maxTime = minTime + selectedRangeMode.seconds
        }
        
        let filteredData = manager.roastGraphData.filter { $0.relativeTime >= minTime && $0.relativeTime <= maxTime }
        
        // RoR 동적 오토 스케일링 설정 (기본 최댓값 25, 초과 시 최대값 자동 갱신)
        let liveMaxRoR = filteredData.compactMap { $0.ror }.max() ?? 0.0
        let guideMaxRoR = manager.guideSession?.graphPoints.compactMap { $0.ror }.max() ?? 0.0
        let rawRorLimit = max(25.0, max(liveMaxRoR, guideMaxRoR))
        let rorLimit = ceil(rawRorLimit / 5.0) * 5.0 // 5의 배수로 올림하여 정갈한 눈금 유지
        let rorScaleFactor = 210.0 / rorLimit
        let rorTicks = stride(from: 0.0, through: rorLimit, by: 5.0).map { $0 }
        let rorDisplayTicks = rorTicks.map { $0 * rorScaleFactor + 20.0 }
        
        return Group {
            Chart {
                // 예열 영역 배경색 (연한 붉은색) - 예열이 끝나고 '투입' 이벤트가 발생한 경우에만 해당 구간을 연한 붉은색으로 칠함
                if manager.roastStartTime != nil {
                    if 0.0 > minTime {
                        RectangleMark(
                            xStart: .value("예열시작", max(minTime, totalMin)),
                            xEnd: .value("예열종료", min(0.0, maxTime)),
                            yStart: .value("Y시작", 0.0),
                            yEnd: .value("Y종료", 240.0)
                        )
                        .foregroundStyle(Color.red.opacity(0.04))
                    }
                }
                
                // 실시간 온도 그래프 (선)
                ForEach(filteredData) { pt in
                    LineMark(
                        x: .value("시간", pt.relativeTime),
                        y: .value("온도", pt.temperature),
                        series: .value("종류", "온도")
                    )
                    .foregroundStyle(Color.appError)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                }
                
                // RoR 그래프 (선) - 30초 단위 필터링을 제거하고 전체 데이터를 매칭하여 부드럽고 촘촘하게 렌더링
                ForEach(filteredData) { pt in
                    if let ror = pt.ror {
                        let displayY = ror * rorScaleFactor + 20.0  // 온도축 0~240에 동적 매핑
                        LineMark(
                            x: .value("시간", pt.relativeTime),
                            y: .value("RoR", displayY),
                            series: .value("종류", "RoR")
                        )
                        .foregroundStyle(Color.green)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }

                // 가이드 기준 곡선 (회색 점선)
                if let guide = manager.guideSession {
                    ForEach(guide.graphPoints) { pt in
                        LineMark(
                            x: .value("기준시간", pt.relativeTime),
                            y: .value("기준온도", pt.temperature),
                            series: .value("종류", "기준온도")
                        )
                        .foregroundStyle(Color.gray.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                    
                    // 가이드 RoR 곡선 (연한 초록 점선) - 솎아내기 없이 부드러운 전체 렌더링
                    ForEach(guide.graphPoints) { pt in
                        if let ror = pt.ror {
                            let displayY = ror * rorScaleFactor + 20.0
                            LineMark(
                                x: .value("기준시간", pt.relativeTime),
                                y: .value("기준RoR", displayY),
                                series: .value("종류", "기준RoR")
                            )
                            .foregroundStyle(Color.green.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                    
                    // 가이드 이벤트 수직선
                    ForEach(guide.events.filter { !["예열 시작", "열량 조절"].contains($0.type) }) { ev in
                        RuleMark(x: .value("가이드이벤트", ev.elapsedSeconds))
                            .foregroundStyle(Color.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .bottom, alignment: .center) {
                                Text(ev.type)
                                    .font(.system(size: 8))
                                    .foregroundColor(.gray.opacity(0.7))
                            }
                    }
                }
                
                // 이벤트 세로 가이드선 표기
                ForEach(manager.roastEvents) { event in
                    if event.elapsedSeconds >= minTime && event.elapsedSeconds <= maxTime {
                        RuleMark(
                            x: .value("시간", event.elapsedSeconds)
                        )
                        .foregroundStyle(eventTypeColor(event.type))
                        .lineStyle(StrokeStyle(lineWidth: event.type == "종료" || event.type == "목표 DTR 도달" ? 2 : 1,
                                               dash: event.type == "예열 시작" || event.type == "열량 조절" ? [4, 4] : []))
                        .annotation(position: .top, alignment: .center) {
                            VStack(spacing: 2) {
                                Text(event.type == "목표 DTR 도달" ? "중지" : event.type)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(eventTypeColor(event.type))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.white.opacity(0.8))
                                    .cornerRadius(3)
                                
                                if event.type == "열량 조절" {
                                    Text("H:\(event.heatValue)")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(eventTypeColor(event.type))
                                }
                            }
                        }
                    }
                }
            }
            .chartXScale(domain: minTime...maxTime)
            .chartYScale(domain: 0...240) // 왜쪽: 온도 0~240°C / 오른쪽: RoR 0~35°C/min 매핑
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.appBorder)
                    AxisValueLabel {
                        if let sec = value.as(Double.self) {
                            let absSec = Int(abs(sec))
                            let m = absSec / 60
                            let s = absSec % 60
                            let sign = sec < 0 ? "-" : ""
                            Text(String(format: "%@%02d:%02d", sign, m, s))
                                .font(.system(size: 9))
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
            }
            .chartYAxis {
                // 왜쪽 축: 온도 (0~240°C)
                AxisMarks(position: .leading, values: [0, 40, 80, 120, 160, 200, 240]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.appBorder)
                    AxisValueLabel {
                        if let temp = value.as(Double.self) {
                            Text(String(format: "%.0f°C", temp))
                                .font(.system(size: 9))
                                .foregroundColor(Color.appError.opacity(0.8))
                        }
                    }
                }
                // 오른쪽 축: RoR (0~rorLimit)
                AxisMarks(position: .trailing, values: rorDisplayTicks) { value in
                    AxisValueLabel {
                        if let displayVal = value.as(Double.self) {
                            let rorVal = (displayVal - 20.0) / rorScaleFactor
                            Text(String(format: "%.0f°C/min", rorVal))
                                .font(.system(size: 8))
                                .foregroundColor(Color.green.opacity(0.8))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Header Connection View
    
    private var headerConnectionView: some View {
        HStack(alignment: .center, spacing: 8) {
            // 기기 정보 및 연결 카드
            HStack(spacing: 12) {
                let nickname = nicknameStore.nickname(for: manager.registeredDeviceUUIDString ?? "")
                Text(nickname ?? manager.registeredDeviceName ?? "등록된 기기 없음")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
                
                if manager.selectedDevice != nil {
                    Button {
                        DeviceDetailWindowController.show(manager: manager, nicknameStore: nicknameStore)
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.appAccent)
                    }
                    .buttonStyle(.plain)
                    .help("장치 세부 정보 보기")
                }
                
                Text(manager.connectionStatusText)
                    .foregroundColor(manager.selectedDevice != nil ? .appSuccess : .textSecondary)
                    .font(.system(size: 11))
                if manager.selectedDevice != nil {
                    Text("RSSI: \(manager.selectedDevice?.rssi ?? 0) dBm")
                        .foregroundColor(.textSecondary)
                        .font(.system(size: 11))
                }
                
                Divider().frame(height: 16)
                
                let isConnected = manager.selectedDevice?.status.isConnected == true
                let hasRegistered = manager.registeredDeviceUUIDString != nil

                if isConnected {
                    Button {
                        manager.unregisterAndDisconnect()
                    } label: {
                        Text("연결 해제")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appError)
                } else if manager.isScanning {
                    Button {
                        manager.stopScanning()
                    } label: {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                            Text("스캔 중지")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appError)
                } else if hasRegistered {
                    Button {
                        manager.connectRegisteredDevice()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "wifi")
                                .font(.system(size: 10))
                            Text("연결하기")
                                .font(.system(size: 11, weight: .bold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                } else {
                    Button {
                        manager.startScanning()
                    } label: {
                        Text("기기 검색")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.appSurface)
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
            
            // 인라인 기기 검색 리스트
            if manager.selectedDevice == nil && (manager.isScanning || !manager.devices.isEmpty) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if manager.devices.isEmpty {
                            Text("기기 찾는 중...")
                                .font(.system(size: 11))
                                .foregroundColor(.textTertiary)
                                .padding(.horizontal, 4)
                        } else {
                            ForEach(manager.devices) { device in
                                Button {
                                    manager.stopScanning()
                                    manager.connect(device)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(device.name)
                                            .font(.system(size: 11, weight: .bold))
                                        Text("\(device.rssi)dBm")
                                            .font(.system(size: 9))
                                            .opacity(0.7)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(Color.appSurface)
                                .cornerRadius(5)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.appBorder, lineWidth: 1))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                }
                .frame(maxWidth: 350)
                .background(Color.appSurface)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
            }
            
            Spacer(minLength: 0)
            
            // 종료 버튼
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("종료")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.appError)
        }
    }

    // MARK: - Helpers


    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let m = Int(interval) / 60
        let s = Int(interval) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func formatDateToElapsed(_ date: Date) -> String {
        guard let preheatStart = manager.preheatStartTime else { return "00:00" }
        let diff = date.timeIntervalSince(preheatStart)
        return formatTimeInterval(diff)
    }

    private func stateColor(_ state: BluetoothManager.RoastState) -> Color {
        switch state {
        case .idle: return .gray
        case .preheating: return .appWarning
        case .roasting: return .appAccent
        case .firstPop: return .orange
        case .secondPop: return .purple
        case .completed: return .appSuccess
        }
    }

    private func eventTypeColor(_ type: String) -> Color {
        switch type {
        case "예열 시작": return .gray
        case "열량 조절": return .yellow
        case "투입": return .blue
        case "T.P": return .purple
        case "1차 팝": return .orange
        case "2차 팝": return .pink
        case "목표 DTR 도달": return .red
        case "종료": return .green
        default: return .gray
        }
    }
}

// MARK: - Device Detail Window Controller

class DeviceDetailWindowController: NSWindowController {
    static var shared: DeviceDetailWindowController?
    
    static func show(manager: BluetoothManager, nicknameStore: NicknameStore) {
        if let shared = shared {
            shared.window?.makeKeyAndOrderFront(nil)
            return
        }
        
        let contentView = DeviceDetailView(manager: manager)
            .environmentObject(nicknameStore)
            .preferredColorScheme(.light)
            .frame(minWidth: 600, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        DeviceDetailWindowController.shared?.close()
                        DeviceDetailWindowController.shared = nil
                    } label: {
                        Text("닫기")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
            }
        
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 700, height: 700))
        window.minSize = NSSize(width: 600, height: 400)
        window.title = "연결된 장치 세부 정보"
        window.titlebarAppearsTransparent = false
        window.titleVisibility = NSWindow.TitleVisibility.visible
        window.styleMask = NSWindow.StyleMask([.titled, .closable, .miniaturizable, .resizable])
        window.isMovableByWindowBackground = true
        window.center()
        
        let controller = DeviceDetailWindowController(window: window)
        self.shared = controller
        controller.showWindow(nil as AnyObject?)
    }
}

struct CustomFocusRingTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(5)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isFocused ? Color.blue.opacity(0.6) : Color(NSColor.separatorColor), lineWidth: isFocused ? 2 : 1)
            )
            .focused($isFocused)
    }
}
