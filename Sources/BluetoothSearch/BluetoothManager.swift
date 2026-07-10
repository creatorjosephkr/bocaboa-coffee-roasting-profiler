import Foundation
import CoreBluetooth
import Combine
import AppKit

// MARK: - BluetoothManager

@MainActor
final class BluetoothManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var bluetoothState: CBManagerState = .unknown
    @Published var isScanning: Bool = false
    @Published var devices: [BLEDevice] = []
    @Published var selectedDevice: BLEDevice?
    @Published var logs: [LogEntry] = []
    @Published var filterServiceUUID: String = ""
    @Published var autoSubscribeNotify: Bool = true
    @Published var showOnlyConnectable: Bool = false
    @Published var temperatureHistory: [TemperatureEntry] = []

    private let maxTemperatureHistory = 300
    @Published var activeAlertMessage: String? = nil
    @Published var targetDeviceDiscovered: BLEDevice? = nil
    private var alertedTargetIdentifiers = Set<UUID>()

    // MARK: - Auto Connection State
    @Published var registeredDeviceUUIDString: String? = UserDefaults.standard.string(forKey: "RegisteredDeviceUUID")
    @Published var registeredDeviceName: String? = UserDefaults.standard.string(forKey: "RegisteredDeviceName")
    @Published var connectionStatusText: String = "미연결"
    @Published var batteryLevel: Int? = nil
    private var autoConnectTimer: Timer?

    // MARK: - Roasting Session State
    @Published var beanName: String = ""
    @Published var processingMethod: String = "워시드 (Washed)"
    @Published var roastPurpose: String = "핸드드립"
    @Published var beanWeight: String = "160"
    @Published var preheatTemp: String = "220"
    @Published var targetDTR: String = "15.0"
    @Published var currentHeat: Int = 12 // 0~12
    
    enum RoastState: String {
        case idle = "대기"
        case preheating = "예열 중"
        case roasting = "로스팅 중 (투입 완료)"
        case firstPop = "1차 팝핑"
        case secondPop = "2차 팝핑"
        case completed = "종료됨"
    }
    @Published var roastState: RoastState = .idle
    
    struct RoastEvent: Identifiable {
        let id = UUID()
        let timestamp: Date
        let elapsedSeconds: TimeInterval
        let temperature: Double
        let heatValue: Int
        let type: String // "예열 시작", "열량 조절", "투입", "1차 팝", "2차 팝", "T.P", "종료", "목표 DTR 도달"
        let description: String
        
        var formattedTime: String {
            let absSec = Int(abs(elapsedSeconds))
            let m = absSec / 60
            let s = absSec % 60
            let sign = elapsedSeconds < 0 ? "-" : ""
            return String(format: "%@%02d:%02d", sign, m, s)
        }
    }
    @Published var roastEvents: [RoastEvent] = []
    @Published var roastStartTime: Date? // 투입 시점
    @Published var preheatStartTime: Date? // 예열 시작 시점
    @Published var elapsedSeconds: TimeInterval = 0
    @Published var savedPreheatDuration: TimeInterval = 0 // 투입 시점까지의 총 예열 시간 저장
    
    var preheatDuration: TimeInterval {
        if roastStartTime != nil {
            return savedPreheatDuration
        } else {
            return elapsedSeconds
        }
    }
    
    var roastDuration: TimeInterval {
        if roastStartTime != nil {
            return elapsedSeconds
        } else {
            return 0.0
        }
    }
    
    @Published var currentRoR: Double = 0.0 // 분당 온도 상승률
    @Published var currentDTR: Double = 0.0 // Development Time Ratio (%)

    // 1차 팝 이후 예상 종료 시각 (목표 DTR 기준)
    @Published var estimatedEndTime: Date? = nil
    @Published var estimatedDevSeconds: TimeInterval = 0 // 예상 디벨롭시간(초)

    // 세션 저장 / 가이드 모드
    @Published var completedSession: RoastSession? = nil   // 종료 시 자동 저장된 세션
    @Published var guideSession: RoastSession? = nil       // 번된 가이드용 기준 세션
    @Published var nextGuideEvent: SavedEvent? = nil       // 다음으로 다가올 가이드 이벤트
    private var guideAlertedTypes = Set<String>()          // 중복 알림 방지
    
    // RoR 계산 설정 (사용자 지정 옵션)
    @Published var rorWindowSize: Double {
        didSet {
            UserDefaults.standard.set(rorWindowSize, forKey: "rorWindowSize")
            recalculateLiveRoR()
        }
    }
    @Published var rorFilterStrength: Double {
        didSet {
            UserDefaults.standard.set(rorFilterStrength, forKey: "rorFilterStrength")
            recalculateLiveRoR()
        }
    }
    
    // 터닝 포인트(T.P) 기록용
    @Published var turningPointTime: Date?
    @Published var turningPointTemp: Double?
    var isTPEstablished: Bool = false
    private var minTempSinceCharge: Double = 999.0
    private var minTempTimeSinceCharge: Date?
    
    // 시간대별 온도 기록 (로스팅 전용 그래프 드로잉용)
    struct RoastDataPoint: Identifiable {
        let id = UUID()
        var relativeTime: TimeInterval // 예열시작시점(t=0) 기준 상대시간 (초)
        let temperature: Double
        let heat: Int
        var ror: Double?
    }
    @Published var roastGraphData: [RoastDataPoint] = []
    
    // 타이머
    private var roastTimer: Timer?
    
    // 알림 재생 여부 기록 (중복 알림 방지)
    private var hasAlertedPreheat: Bool = false
    private var hasAlertedDTR: Bool = false

    // MARK: - Private

    private var centralManager: CBCentralManager!
    private var peripheralMap: [UUID: BLEDevice] = [:]

    // MARK: - Init

    override init() {
        let savedWindow = UserDefaults.standard.double(forKey: "rorWindowSize")
        self.rorWindowSize = savedWindow > 0 ? savedWindow : 15.0
        
        let savedFilter = UserDefaults.standard.object(forKey: "rorFilterStrength") as? Double
        self.rorFilterStrength = savedFilter ?? 90.0
        
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Roasting Sequence Methods

    private func checkConnection() -> Bool {
        if !(selectedDevice?.status.isConnected ?? false) {
            let alert = NSAlert()
            alert.messageText = "장치 연결 알림"
            alert.informativeText = "장치가 연결되어 있지 않습니다. 블루투스 기기를 먼저 연결해 주세요."
            alert.addButton(withTitle: "확인")
            
            if let path = Bundle.main.path(forResource: "bluetooth-off", ofType: "svg"),
               let image = NSImage(contentsOfFile: path) {
                image.size = NSSize(width: 64, height: 64)
                alert.icon = image
            }
            
            alert.runModal()
            return false
        }
        return true
    }

    func cancelRoasting() {
        stopRoastingTimer()
        roastState = .idle
        preheatStartTime = nil
        roastStartTime = nil
        elapsedSeconds = 0
        currentRoR = 0.0
        currentDTR = 0.0
        turningPointTime = nil
        turningPointTemp = nil
        isTPEstablished = false
        minTempSinceCharge = 999.0
        roastEvents.removeAll()
        roastGraphData.removeAll()
        estimatedEndTime = nil
        estimatedDevSeconds = 0
        hasAlertedPreheat = false
        hasAlertedDTR = false
        addLog("로스팅 취소됨", type: .info)
    }

    func restartRoasting() {
        guard checkConnection() else { return }
        cancelRoasting()
        startPreheating()
    }

    func startPreheating() {
        guard checkConnection() else { return }
        stopRoastingTimer()
        roastState = .preheating
        preheatStartTime = Date()
        roastStartTime = nil
        elapsedSeconds = 0
        currentRoR = 0.0
        currentDTR = 0.0
        turningPointTime = nil
        turningPointTemp = nil
        isTPEstablished = false
        minTempSinceCharge = 999.0
        roastEvents.removeAll()
        roastGraphData.removeAll()
        estimatedEndTime = nil
        savedPreheatDuration = 0
        estimatedDevSeconds = 0
        hasAlertedPreheat = false
        hasAlertedDTR = false
        
        let initialTemp = temperatureHistory.first?.celsius ?? 0.0
        let event = RoastEvent(
            timestamp: Date(),
            elapsedSeconds: 0,
            temperature: initialTemp,
            heatValue: currentHeat,
            type: "예열 시작",
            description: "예열 시작 (설정 온도: \(preheatTemp)°C, 설정 열량: \(currentHeat))"
        )
        roastEvents.append(event)
        
        // 현재 온도가 이미 목표 예열 온도를 만족한다면 첫 데이터 포인트에서 바로 연동할 수 있도록 함
        startRoastingTimer()
        addLog("로스팅 세션 예열 시작", type: .info)
    }

    func chargeBeans() {
        guard checkConnection() else { return }
        guard roastState == .preheating else { return }
        roastState = .roasting
        
        let now = Date()
        roastStartTime = now
        minTempSinceCharge = temperatureHistory.first?.celsius ?? 999.0
        minTempTimeSinceCharge = now
        isTPEstablished = false
        
        // 투입 시점까지의 총 예열 시간 확정
        let preheatTime = now.timeIntervalSince(preheatStartTime ?? now)
        self.savedPreheatDuration = preheatTime
        
        // 메인 elapsedSeconds 타이머를 즉시 0초로 리셋
        self.elapsedSeconds = 0.0
        
        // 1. 지금까지 수집된 예열 그래프 데이터(roastGraphData)의 시간축을 투입 시점 0 기준으로 소급 보정 (음수화)
        self.roastGraphData = self.roastGraphData.map { pt in
            var newPt = pt
            newPt.relativeTime = pt.relativeTime - preheatTime
            return newPt
        }
        
        // 2. 지금까지 수집된 예열 이벤트(roastEvents)의 시간축을 소급 보정
        self.roastEvents = self.roastEvents.map { ev in
            return RoastEvent(
                timestamp: ev.timestamp,
                elapsedSeconds: ev.elapsedSeconds - preheatTime,
                temperature: ev.temperature,
                heatValue: ev.heatValue,
                type: ev.type,
                description: ev.description
            )
        }
        
        // 3. 투입 이벤트 추가 (elapsedSeconds = 0.0)
        let currentTemp = temperatureHistory.first?.celsius ?? 0.0
        let event = RoastEvent(
            timestamp: now,
            elapsedSeconds: 0.0,
            temperature: currentTemp,
            heatValue: currentHeat,
            type: "투입",
            description: "생두 투입 (투입량: \(beanWeight)g, 투입온도: \(String(format: "%.1f", currentTemp))°C)"
        )
        roastEvents.append(event)
        addLog("생두 투입 완료", type: .info)
    }

    func triggerFirstPop() {
        guard checkConnection() else { return }
        guard roastState == .roasting else { return }
        roastState = .firstPop
        let now = Date()
        let currentTemp = temperatureHistory.first?.celsius ?? 0.0
        let elapsed = now.timeIntervalSince(roastStartTime ?? preheatStartTime ?? now)
        let event = RoastEvent(
            timestamp: now,
            elapsedSeconds: elapsed,
            temperature: currentTemp,
            heatValue: currentHeat,
            type: "1차 팝",
            description: "1차 팝핑 시작 (온도: \(String(format: "%.1f", currentTemp))°C)"
        )
        roastEvents.append(event)
        addLog("1차 팝핑 감지", type: .info)

        // ─── 예상 종료 시각 계산 ───
        // DTR = 디벨롭시간 / 총로스팅시간
        // 투입 시각 기준 T_fc = 1차팝까지 경과
        // 예상 디벨롭시간 = T_fc × DTR / (100 - DTR)
        if let chargeEvent = roastEvents.first(where: { $0.type == "투입" }),
           let dtr = Double(targetDTR), dtr > 0, dtr < 100 {
            let T_fc = now.timeIntervalSince(roastStartTime ?? preheatStartTime ?? now) - chargeEvent.elapsedSeconds
            let devSec = T_fc * dtr / (100.0 - dtr)
            estimatedDevSeconds = devSec
            estimatedEndTime = now.addingTimeInterval(devSec)
            let m = Int(devSec) / 60
            let s = Int(devSec) % 60
            addLog(
                String(format: "예상 종료까지 %02d:%02d (디벨롭시간 목표 %.1f%%)", m, s, dtr),
                type: .info
            )
        }
    }

    func triggerSecondPop() {
        guard checkConnection() else { return }
        guard roastState == .firstPop else { return }
        roastState = .secondPop
        let currentTemp = temperatureHistory.first?.celsius ?? 0.0
        let elapsed = Date().timeIntervalSince(roastStartTime ?? preheatStartTime ?? Date())
        let event = RoastEvent(
            timestamp: Date(),
            elapsedSeconds: elapsed,
            temperature: currentTemp,
            heatValue: currentHeat,
            type: "2차 팝",
            description: "2차 팝핑 시작 (온도: \(String(format: "%.1f", currentTemp))°C)"
        )
        roastEvents.append(event)
        addLog("2차 팝핑 감지", type: .info)
    }

    func finishRoasting() {
        guard checkConnection() else { return }
        guard roastState != .idle && roastState != .completed else { return }
        roastState = .completed
        stopRoastingTimer()
        
        let currentTemp = temperatureHistory.first?.celsius ?? 0.0
        let elapsed = Date().timeIntervalSince(roastStartTime ?? preheatStartTime ?? Date())
        
        var extraDesc = ""
        if let firstPopEvent = roastEvents.first(where: { $0.type == "1차 팝" }),
           let chargeEvent = roastEvents.first(where: { $0.type == "투입" }) {
            let totalRoastTime = elapsed - chargeEvent.elapsedSeconds
            let devTime = elapsed - firstPopEvent.elapsedSeconds
            let dtr = (devTime / totalRoastTime) * 100.0
            extraDesc = String(format: ", DTR: %.1f%%, 디벨롭시간: %d초", dtr, Int(devTime))
        }
        
        let event = RoastEvent(
            timestamp: Date(),
            elapsedSeconds: elapsed,
            temperature: currentTemp,
            heatValue: currentHeat,
            type: "종료",
            description: "로스팅 종료 (배출온도: \(String(format: "%.1f", currentTemp))°C\(extraDesc))"
        )
        roastEvents.append(event)
        addLog("로스팅 종료 완료", type: .info)

        // 원두 이름이 입력되지 않은 경우 완료 일자와 시간을 이름으로 자동 설정
        if beanName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            self.beanName = formatter.string(from: Date())
        }

        // 세션 자동 저장
        let session = RoastSession(
            beanName: beanName,
            beanWeight: beanWeight,
            preheatTemp: preheatTemp,
            targetDTR: targetDTR,
            events: roastEvents,
            graphPoints: roastGraphData
        )
        completedSession = session
    }

    func adjustHeat(to newValue: Int) {
        guard checkConnection() else { return }
        let oldHeat = currentHeat
        currentHeat = max(0, min(12, newValue))
        
        if roastState != .idle && roastState != .completed {
            let currentTemp = temperatureHistory.first?.celsius ?? 0.0
            let elapsed = Date().timeIntervalSince(roastStartTime ?? preheatStartTime ?? Date())
            let event = RoastEvent(
                timestamp: Date(),
                elapsedSeconds: elapsed,
                temperature: currentTemp,
                heatValue: currentHeat,
                type: "열량 조절",
                description: "열량 변경: \(oldHeat) → \(currentHeat)"
            )
            roastEvents.append(event)
            addLog("열량 조절: \(currentHeat)", type: .info)
        }
    }

    private func startRoastingTimer() {
        roastTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if let roastStart = self.roastStartTime {
                    self.elapsedSeconds = Date().timeIntervalSince(roastStart)
                } else if let preheatStart = self.preheatStartTime {
                    self.elapsedSeconds = Date().timeIntervalSince(preheatStart)
                }
            }
        }
    }
    
    private func stopRoastingTimer() {
        roastTimer?.invalidate()
        roastTimer = nil
    }

    // MARK: - Roasting Event Processing

    func processIncomingTemperature(_ temp: Double) {
        guard roastState != .idle && roastState != .completed else { return }
        
        let now = Date()
        let elapsed: TimeInterval
        if let roastStart = roastStartTime {
            elapsed = now.timeIntervalSince(roastStart)
        } else {
            elapsed = now.timeIntervalSince(preheatStartTime ?? now)
        }
        // 1. RoR 계산 (최근 30초 상승폭을 분당 상승률로 환산)
        // 생두 투입 후 1분이 지나야 측정 시작
        var calculatedRoR: Double? = nil
        var shouldCalculateRoR = false
        if let chargeEvent = roastEvents.first(where: { $0.type == "투입" }) {
            if elapsed - chargeEvent.elapsedSeconds >= 60.0 {
                shouldCalculateRoR = true
            }
        }
        
        if shouldCalculateRoR {
            let targetTime = elapsed - rorWindowSize
            if let prevPoint = roastGraphData.first(where: { $0.relativeTime >= targetTime }) {
                let tempDiff = temp - prevPoint.temperature
                let timeDiff = elapsed - prevPoint.relativeTime
                let minTimeDiff = min(5.0, rorWindowSize / 2.0)
                if timeDiff > minTimeDiff {
                    let rawRoR = (tempDiff / timeDiff) * 60.0
                    var smoothedRoR = rawRoR
                    
                    // EMA (Exponential Moving Average) 적용하여 스무딩
                    if let lastRoR = roastGraphData.last(where: { $0.ror != nil })?.ror {
                        let alpha = (100.0 - rorFilterStrength) / 100.0
                        smoothedRoR = (rawRoR * alpha) + (lastRoR * (1.0 - alpha))
                    }
                    
                    // 마이너스 값 방지 (0으로 클램핑)
                    calculatedRoR = max(0.0, smoothedRoR)
                    self.currentRoR = calculatedRoR!
                }
            }
        } else {
            self.currentRoR = 0.0
        }
        
        let point = RoastDataPoint(relativeTime: elapsed, temperature: temp, heat: currentHeat, ror: calculatedRoR)
        roastGraphData.append(point)
        
        // 2. T.P (터닝 포인트) 계산
        if roastState == .roasting || roastState == .firstPop || roastState == .secondPop {
            if !isTPEstablished {
                if temp < minTempSinceCharge {
                    minTempSinceCharge = temp
                    minTempTimeSinceCharge = Date()
                } else if temp > minTempSinceCharge + 0.5 {
                    isTPEstablished = true
                    turningPointTime = minTempTimeSinceCharge
                    turningPointTemp = minTempSinceCharge
                    
                    let tpElapsed = (minTempTimeSinceCharge ?? Date()).timeIntervalSince(roastStartTime ?? preheatStartTime ?? Date())
                    let event = RoastEvent(
                        timestamp: minTempTimeSinceCharge ?? Date(),
                        elapsedSeconds: tpElapsed,
                        temperature: minTempSinceCharge,
                        heatValue: currentHeat,
                        type: "T.P",
                        description: String(format: "터닝 포인트 (T.P) 감지: %.1f°C", minTempSinceCharge)
                    )
                    roastEvents.append(event)
                    addLog("T.P 감지됨: \(String(format: "%.1f", minTempSinceCharge))°C", type: .info)
                }
            }
        }
        
        // 3. 예열 온도 도달 알림
        if roastState == .preheating, let targetPreheat = Double(preheatTemp) {
            if temp >= targetPreheat && !hasAlertedPreheat {
                hasAlertedPreheat = true
                playPreheatAlert()
            }
        }
        
        // 4. DTR 계산 및 알림
        if let firstPopEvent = roastEvents.first(where: { $0.type == "1차 팝" }),
           let chargeEvent = roastEvents.first(where: { $0.type == "투입" }) {
            let totalTime = elapsed - chargeEvent.elapsedSeconds
            let devTime = elapsed - firstPopEvent.elapsedSeconds
            if totalTime > 0 {
                self.currentDTR = (devTime / totalTime) * 100.0

                if let targetDtrVal = Double(targetDTR) {
                    if self.currentDTR >= targetDtrVal && !hasAlertedDTR {
                        hasAlertedDTR = true
                        playDTRAlert()
                    }
                }
            }
        }

        // 5. 가이드 모드: 다음 이벤트 시점 알림
        updateGuideAlerts(elapsed: elapsed)
    }

    /// 실시간으로 쌓인 데이터의 RoR을 설정값에 맞게 전체 재계산
    func recalculateLiveRoR() {
        let chargeTime = roastEvents.first(where: { $0.type == "투입" })?.elapsedSeconds ?? 0.0
        
        for i in 0..<roastGraphData.count {
            let pt = roastGraphData[i]
            let elapsed = pt.relativeTime
            
            let shouldCalculate = (elapsed - chargeTime >= 60.0)
            
            if shouldCalculate {
                let targetTime = elapsed - rorWindowSize
                if let prevPoint = roastGraphData[0..<i].first(where: { $0.relativeTime >= targetTime }) {
                    let tempDiff = pt.temperature - prevPoint.temperature
                    let timeDiff = elapsed - prevPoint.relativeTime
                    let minTimeDiff = min(5.0, rorWindowSize / 2.0)
                    if timeDiff > minTimeDiff {
                        let rawRoR = (tempDiff / timeDiff) * 60.0
                        var smoothedRoR = rawRoR
                        
                        var lastRoR: Double? = nil
                        for j in (0..<i).reversed() {
                            if let prevRor = roastGraphData[j].ror {
                                lastRoR = prevRor
                                break
                            }
                        }
                        
                        if let lastR = lastRoR {
                            let alpha = (100.0 - rorFilterStrength) / 100.0
                            smoothedRoR = (rawRoR * alpha) + (lastR * (1.0 - alpha))
                        }
                        
                        roastGraphData[i].ror = max(0.0, smoothedRoR)
                    }
                }
            } else {
                roastGraphData[i].ror = nil
            }
        }
        
        if let lastValidRor = roastGraphData.last(where: { $0.ror != nil })?.ror {
            self.currentRoR = lastValidRor
        } else {
            self.currentRoR = 0.0
        }
    }

    private func playPreheatAlert() {
        // macOS Glass 사운드 비동기 재생
        if let sound = NSSound(named: "Glass") {
            sound.play()
        }
        self.activeAlertMessage = "목표 예열 온도 \(preheatTemp)°C에 도달했습니다."
        addLog("예열 완료! 설정 온도 도달.", type: .info)
    }
    
    private func playDTRAlert() {
        if let sound = NSSound(named: "Basso") {
            sound.play()
        }
        self.activeAlertMessage = String(format: "목표 DTR %.1f%%에 도달했습니다! 로스팅을 중지해 주세요.", currentDTR)
        addLog("목표 DTR 도달! 중지 알림.", type: .warning)
        
        let elapsed = Date().timeIntervalSince(preheatStartTime ?? Date())
        let event = RoastEvent(
            timestamp: Date(),
            elapsedSeconds: elapsed,
            temperature: temperatureHistory.first?.celsius ?? 0.0,
            heatValue: currentHeat,
            type: "목표 DTR 도달",
            description: String(format: "목표 DTR %.1f%% 도달", currentDTR)
        )
        roastEvents.append(event)
    }

    // MARK: - Guide Mode

    /// 가이드 세션 설정 (참조 기준 선 설정)
    func setGuideSession(_ session: RoastSession?) {
        guard var updatedSession = session else {
            guideSession = nil
            guideAlertedTypes.removeAll()
            nextGuideEvent = nil
            return
        }
        
        // ─── 구버전 세션 시간축 보정 (투입 시점을 0초로 리셋) ───
        if let chargeEvent = updatedSession.events.first(where: { $0.type == "생두 투입" || $0.type == "투입" || $0.type.contains("투입") }),
           chargeEvent.elapsedSeconds > 0 {
            let offset = chargeEvent.elapsedSeconds
            
            updatedSession.events = updatedSession.events.map { ev in
                var newEv = ev
                newEv.elapsedSeconds = ev.elapsedSeconds - offset
                return newEv
            }
            
            updatedSession.graphPoints = updatedSession.graphPoints.map { pt in
                var newPt = pt
                newPt.relativeTime = pt.relativeTime - offset
                return newPt
            }
        }
        
        // 가이드 세션의 ror이 누락되었거나 새로 갱신이 필요한 경우를 대비해 ror을 재계산하여 주입
        // "생두 투입" 또는 "투입" 등 투입 관련 이벤트를 유연하게 찾고, 없으면 0초 기준으로 폴백
        let chargeTime = updatedSession.events.first(where: { $0.type == "생두 투입" || $0.type == "투입" || $0.type.contains("투입") })?.elapsedSeconds ?? 0.0
        var recalculatedPoints = updatedSession.graphPoints
        
        for i in 0..<recalculatedPoints.count {
            let pt = recalculatedPoints[i]
            let elapsed = pt.relativeTime
            
            // ror 계산 여부 결정 (투입 이후 60초가 지났는지 확인)
            let shouldCalculate = (elapsed - chargeTime >= 60.0)
            
            if shouldCalculate {
                let targetTime = elapsed - rorWindowSize
                // 자기 자신 또는 미래 포인트를 참조하지 않도록 검색 범위를 이전 포인트들(0..<i)로 제한
                if let prevPoint = recalculatedPoints[0..<i].first(where: { $0.relativeTime >= targetTime }) {
                    let tempDiff = pt.temperature - prevPoint.temperature
                    let timeDiff = elapsed - prevPoint.relativeTime
                    let minTimeDiff = min(5.0, rorWindowSize / 2.0)
                    if timeDiff > minTimeDiff {
                        let rawRoR = (tempDiff / timeDiff) * 60.0
                        var smoothedRoR = rawRoR
                        
                        // 이전 포인트의 ror을 찾아 EMA 적용
                        var lastRoR: Double? = nil
                        for j in (0..<i).reversed() {
                            if let prevRor = recalculatedPoints[j].ror {
                                lastRoR = prevRor
                                break
                            }
                        }
                        
                        if let lastR = lastRoR {
                            let alpha = (100.0 - rorFilterStrength) / 100.0
                            smoothedRoR = (rawRoR * alpha) + (lastR * (1.0 - alpha))
                        }
                        
                        recalculatedPoints[i].ror = max(0.0, smoothedRoR)
                    }
                }
            } else {
                recalculatedPoints[i].ror = nil
            }
        }
        updatedSession.graphPoints = recalculatedPoints
        
        guideSession = updatedSession
        guideAlertedTypes.removeAll()
        updateNextGuideEvent(elapsed: elapsedSeconds)
        
        // 가이드 모드 설정 시 이전 기록의 설정값 적용
        beanName = updatedSession.beanName
        beanWeight = updatedSession.beanWeight
        preheatTemp = updatedSession.preheatTemp
        targetDTR = updatedSession.targetDTR
        
        // 초기 열량 설정 (예열 시작 이벤트 또는 첫 번째 그래프 포인트 참조)
        if let preheatEvent = updatedSession.events.first(where: { $0.type == "예열 시작" }) {
            currentHeat = preheatEvent.heatValue
        } else if let firstPoint = updatedSession.graphPoints.first {
            currentHeat = firstPoint.heat
        }
    }

    private func updateGuideAlerts(elapsed: TimeInterval) {
        guard let guide = guideSession else { return }

        // 다음 이벤트 갱신
        let upcoming = guide.events
            .filter { ev in
                !guideAlertedTypes.contains(ev.type) &&
                !["예열 시작", "열량 조절"].contains(ev.type)
            }
            .sorted { $0.elapsedSeconds < $1.elapsedSeconds }

        nextGuideEvent = upcoming.first

        // 30초 전 경고 알림
        if let next = upcoming.first {
            let timeToEvent = next.elapsedSeconds - elapsed
            if timeToEvent > 0 && timeToEvent <= 30 && !guideAlertedTypes.contains("warn_" + next.type) {
                guideAlertedTypes.insert("warn_" + next.type)
                NSSound(named: "Funk")?.play()
                addLog(String(format: "⏰ 가이드: '%@' %.0f초 후", next.type, timeToEvent), type: .info)
            }
            // 시점 도달
            if timeToEvent <= 0 {
                guideAlertedTypes.insert(next.type)
                NSSound(named: "Ping")?.play()
                addLog("🔔 가이드: '\(next.type)' 시점도달", type: .warning)
            }
        }
    }

    private func updateNextGuideEvent(elapsed: TimeInterval) {
        guard let guide = guideSession else { nextGuideEvent = nil; return }
        nextGuideEvent = guide.events
            .filter { !guideAlertedTypes.contains($0.type) && $0.elapsedSeconds > elapsed }
            .sorted { $0.elapsedSeconds < $1.elapsedSeconds }
            .first
    }

    // MARK: - Scanning

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            addLog("Bluetooth가 활성화되지 않았습니다.", type: .warning)
            return
        }
        devices.removeAll()
        peripheralMap.removeAll()
        alertedTargetIdentifiers.removeAll()

        let services: [CBUUID]?
        let trimmed = filterServiceUUID.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            services = nil
        } else {
            // Accept comma-separated UUIDs
            services = trimmed.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map { CBUUID(string: $0) }
        }

        centralManager.scanForPeripherals(
            withServices: services,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
        addLog(services == nil
               ? "전체 BLE 기기 스캔 시작"
               : "필터 스캔 시작: \(trimmed)",
               type: .info)
    }

    func stopScanning() {
        guard isScanning else { return }
        centralManager.stopScan()
        isScanning = false
        addLog("스캔 중지 (\(devices.count)개 발견)", type: .info)
    }

    // MARK: - Connection

    func connect(_ device: BLEDevice) {
        guard !device.status.isConnected else { return }
        
        // 보카보아 기기 검증
        let isTarget = (device.name == "PRL-SPP-03") || (device.peripheral.name == "PRL-SPP-03")
        guard isTarget else {
            addLog("연결 거부: 보카보아 기기가 아닙니다. (\(device.name))", type: .error)
            return
        }
        
        device.status = .connecting
        centralManager.connect(device.peripheral, options: nil)
        addLog("연결 시도: \(device.name)", type: .info, device: device.name)
    }

    func disconnect(_ device: BLEDevice) {
        centralManager.cancelPeripheralConnection(device.peripheral)
        addLog("연결 해제 요청: \(device.name)", type: .warning, device: device.name)
    }

    func unregisterAndDisconnect() {
        self.autoConnectTimer?.invalidate()
        
        if let device = selectedDevice {
            centralManager.cancelPeripheralConnection(device.peripheral)
            self.selectedDevice = nil
        }
        
        if let uuidString = self.registeredDeviceUUIDString,
           let uuid = UUID(uuidString: uuidString) {
            let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
            if let peripheral = peripherals.first {
                centralManager.cancelPeripheralConnection(peripheral)
            }
        }
        
        UserDefaults.standard.removeObject(forKey: "RegisteredDeviceUUID")
        UserDefaults.standard.removeObject(forKey: "RegisteredDeviceName")
        self.registeredDeviceUUIDString = nil
        self.registeredDeviceName = nil
        self.connectionStatusText = "미연결"
        self.batteryLevel = nil

        addLog("기기 등록 해제 및 연결 끊기 완료", type: .warning)
        // 수동 연결 대기 — 자동 startScanning() 안 함
    }

    /// 등록된 기기로 수동 연결 시도 ("연결하기" 버튼 트리거)
    func connectRegisteredDevice() {
        guard let uuidString = registeredDeviceUUIDString,
              let uuid = UUID(uuidString: uuidString) else {
            startScanning()
            return
        }
        
        // 만약 등록된 기기의 이름이 보카보아(PRL-SPP-03)가 아니라면 등록 정보를 강제로 지우고 스캔을 시작함
        if let regName = registeredDeviceName, regName != "PRL-SPP-03" && regName != "Vocaboca" {
            addLog("등록된 기기 정보가 보카보아가 아닙니다. 등록을 초기화합니다.", type: .warning)
            UserDefaults.standard.removeObject(forKey: "RegisteredDeviceUUID")
            UserDefaults.standard.removeObject(forKey: "RegisteredDeviceName")
            self.registeredDeviceUUIDString = nil
            self.registeredDeviceName = nil
            self.connectionStatusText = "미연결"
            startScanning()
            return
        }
        
        connectionStatusText = "연결 시도 중..."
        addLog("등록된 기기에 연결 시도 (\(registeredDeviceName ?? uuidString))", type: .info)

        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [uuid])
        if let peripheral = peripherals.first {
            // 가져온 기기의 이름이 보카보아가 아니면 연결 거부 및 등록 정보 초기화
            let localName = peripheral.name ?? ""
            guard localName == "PRL-SPP-03" || localName == "Vocaboca" else {
                addLog("가져온 기기(\(localName))가 보카보아가 아닙니다. 연결을 취소하고 등록 정보를 초기화합니다.", type: .error)
                UserDefaults.standard.removeObject(forKey: "RegisteredDeviceUUID")
                UserDefaults.standard.removeObject(forKey: "RegisteredDeviceName")
                self.registeredDeviceUUIDString = nil
                self.registeredDeviceName = nil
                self.connectionStatusText = "미연결"
                startScanning()
                return
            }
            
            let device: BLEDevice
            if let existing = peripheralMap[uuid] {
                device = existing
            } else {
                device = BLEDevice(peripheral: peripheral, rssi: -127, advertisementData: [:])
                peripheralMap[uuid] = device
            }
            connect(device)

            autoConnectTimer?.invalidate()
            autoConnectTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    if !(self.selectedDevice?.status.isConnected ?? false) {
                        self.addLog("연결 타임아웃. 검색 모드로 전환.", type: .warning)
                        self.connectionStatusText = "연결 실패 — 검색 중"
                        self.startScanning()
                    }
                }
            }
        } else {
            addLog("등록된 기기를 찾지 못함. 검색을 시작합니다.", type: .info)
            connectionStatusText = "검색 중..."
            startScanning()
        }
    }

    // MARK: - Characteristic Operations

    func readValue(for characteristic: BLECharacteristic, peripheral: CBPeripheral) {
        guard characteristic.canRead else { return }
        peripheral.readValue(for: characteristic.characteristic)
        addLog("값 읽기 요청: \(characteristic.displayName)", type: .info)
    }

    func toggleNotify(for characteristic: BLECharacteristic, peripheral: CBPeripheral) {
        guard characteristic.canNotify else { return }
        let newState = !characteristic.isNotifying
        peripheral.setNotifyValue(newState, for: characteristic.characteristic)
    }

    func writeValue(_ data: Data, for characteristic: BLECharacteristic, peripheral: CBPeripheral) {
        guard characteristic.canWrite else { return }
        let writeType: CBCharacteristicWriteType = characteristic.characteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse
        peripheral.writeValue(data, for: characteristic.characteristic, type: writeType)
        addLog("쓰기: \(characteristic.displayName) → \(data.hexString)", type: .info)
    }

    // MARK: - Log Management

    func clearLogs() {
        logs.removeAll()
    }

    func exportLogs() -> String {
        logs.reversed().map { entry in
            "[\(entry.formattedTime)] [\(entry.type.rawValue)] \(entry.deviceName.map { "[\($0)] " } ?? "")\(entry.message)"
        }.joined(separator: "\n")
    }

    // MARK: - Private Helpers

    private func addLog(_ message: String, type: LogEntry.LogType, device: String? = nil) {
        let entry = LogEntry(message: message, type: type, deviceName: device)
        logs.insert(entry, at: 0)
        if logs.count > 1000 { logs.removeLast(logs.count - 1000) }
    }

    private func device(for peripheral: CBPeripheral) -> BLEDevice? {
        peripheralMap[peripheral.identifier]
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.bluetoothState = central.state
            switch central.state {
            case .poweredOn:
                self.addLog("Bluetooth 준비됨 ✓", type: .info)
                // 자동 연결 안 함 — '연결하기' 버튼으로 수동 연결
                if self.registeredDeviceUUIDString != nil {
                    self.connectionStatusText = "연결 대기 중 ('연결하기' 버튼 누르세요)"
                    self.addLog("등록된 기기 있음. '연결하기' 버튼으로 연결하세요.", type: .info)
                } else {
                    self.startScanning()
                }
            case .poweredOff:
                self.addLog("Bluetooth가 꺼져 있습니다.", type: .warning)
                self.isScanning = false
            case .unauthorized:
                self.addLog("Bluetooth 권한이 없습니다. 시스템 환경설정을 확인하세요.", type: .error)
            case .unsupported:
                self.addLog("이 기기는 Bluetooth LE를 지원하지 않습니다.", type: .error)
            case .resetting:
                self.addLog("Bluetooth 재설정 중...", type: .warning)
            default:
                break
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let isTarget = (localName == "PRL-SPP-03") || (peripheral.name == "PRL-SPP-03")
            guard isTarget else { return } // 보카보아 기기가 아니면 완전히 무시

            let rssiValue = RSSI.intValue
            let id = peripheral.identifier

            if let existing = self.peripheralMap[id] {
                // Update RSSI and advertisement data for known devices
                existing.rssi = rssiValue
                existing.lastSeen = Date()
                
                // 타겟 장비 감지 알림
                if !self.alertedTargetIdentifiers.contains(existing.id) && self.targetDeviceDiscovered == nil && self.selectedDevice == nil {
                    self.alertedTargetIdentifiers.insert(existing.id)
                    self.targetDeviceDiscovered = existing
                }
            } else {
                // New device
                let device = BLEDevice(
                    peripheral: peripheral,
                    rssi: rssiValue,
                    advertisementData: advertisementData
                )
                self.peripheralMap[id] = device

                if self.showOnlyConnectable && !device.isConnectable { return }

                self.devices.append(device)

                self.addLog(
                    "발견: \(device.name)  [\(rssiValue) dBm]",
                    type: .discovered
                )
                
                // 타겟 장비 감지 알림
                if !self.alertedTargetIdentifiers.contains(device.id) && self.targetDeviceDiscovered == nil && self.selectedDevice == nil {
                    self.alertedTargetIdentifiers.insert(device.id)
                    self.targetDeviceDiscovered = device
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            guard let device = self.device(for: peripheral) else { return }
            device.status = .connected
            device.services.removeAll()
            peripheral.delegate = self
            peripheral.discoverServices(nil)
            
            // 등록된 기기 정보 저장
            self.autoConnectTimer?.invalidate()
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: "RegisteredDeviceUUID")
            UserDefaults.standard.set(peripheral.name ?? "Vocaboca", forKey: "RegisteredDeviceName")
            self.registeredDeviceUUIDString = peripheral.identifier.uuidString
            self.registeredDeviceName = peripheral.name ?? "Vocaboca"
            self.connectionStatusText = "연결됨"
            
            self.selectedDevice = device
            self.stopScanning()
            self.addLog("연결됨: \(device.name)", type: .connected, device: device.name)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            guard let device = self.device(for: peripheral) else { return }
            let msg = error?.localizedDescription ?? "알 수 없는 오류"
            device.status = .failed(msg)
            self.connectionStatusText = "연결 실패 — '연결하기' 버튼으로 다시 시도하세요"
            self.autoConnectTimer?.invalidate()
            self.addLog("연결 실패: \(device.name) — \(msg)", type: .error, device: device.name)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            guard let device = self.device(for: peripheral) else { return }
            device.status = .disconnected
            device.services.removeAll()
            self.batteryLevel = nil
            self.autoConnectTimer?.invalidate()
            self.selectedDevice = nil
            self.addLog("연결 해제: \(device.name)", type: .warning, device: device.name)

            // 자동 재연결 안 함 — 사용자를 버튼으로 수동 재연결
            if self.registeredDeviceUUIDString != nil {
                self.connectionStatusText = "연결 해제됨 — '연결하기' 버튼으로 재연결 가능"
            } else {
                self.connectionStatusText = "미연결"
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let device = self.device(for: peripheral) else { return }
            if let error = error {
                self.addLog("서비스 검색 오류: \(error.localizedDescription)", type: .error, device: device.name)
                return
            }
            guard let services = peripheral.services else { return }

            let bleServices = services.map { BLEService(service: $0) }
            device.services = bleServices

            for service in services {
                peripheral.discoverCharacteristics(nil, for: service)
            }
            self.addLog(
                "서비스 \(services.count)개 발견",
                type: .info, device: device.name
            )
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            guard let device = self.device(for: peripheral) else { return }
            if let error = error {
                self.addLog("특성 검색 오류: \(error.localizedDescription)", type: .error, device: device.name)
                return
            }
            guard let characteristics = service.characteristics,
                  let bleService = device.services.first(where: { $0.service.uuid == service.uuid })
            else { return }

            bleService.characteristics = characteristics.map { BLECharacteristic(characteristic: $0) }

            // Auto-read readable characteristics
            for char in characteristics where char.properties.contains(.read) {
                peripheral.readValue(for: char)
            }
            // Auto-subscribe to notify/indicate if enabled
            if self.autoSubscribeNotify {
                for char in characteristics where char.properties.contains(.notify) || char.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: char)
                }
            }

            self.addLog(
                "특성 \(characteristics.count)개 발견 [\(BluetoothUUIDHelper.serviceDisplayName(for: service.uuid))]",
                type: .info, device: device.name
            )
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            guard let device = self.device(for: peripheral) else { return }
            if let error = error {
                self.addLog("값 읽기 오류: \(error.localizedDescription)", type: .error, device: device.name)
                return
            }

            // Find the matching BLECharacteristic and update
            for service in device.services {
                if let bleChar = service.characteristics.first(where: { $0.characteristic.uuid == characteristic.uuid }) {
                    bleChar.value = characteristic.value
                    bleChar.lastUpdated = Date()
                    bleChar.updateCount += 1

                    if let data = characteristic.value, !data.isEmpty {
                        self.addLog(
                            "[\(bleChar.shortUUID)] \(data.hexString)  (\(data.count) bytes)",
                            type: .data, device: device.name
                        )
                        // 표준 배터리 서비스 (2A19) 대응
                        if characteristic.uuid == CBUUID(string: "2A19") {
                            self.batteryLevel = Int(data[0])
                        }
                        // 온도 데이터 자동 디코딩
                        if let temp = DataDecoder.extractTemperature(data) {
                            let entry = TemperatureEntry(
                                timestamp: Date(),
                                celsius: temp,
                                deviceName: device.name
                            )
                            self.temperatureHistory.insert(entry, at: 0)
                            if self.temperatureHistory.count > self.maxTemperatureHistory {
                                self.temperatureHistory.removeLast()
                            }
                            
                            // 패킷에서 배터리 레벨 추출 시도
                            if let battery = DataDecoder.extractBatteryLevel(data) {
                                self.batteryLevel = battery
                            }

                            // 로스팅 실시간 프로세싱 연동
                            self.processIncomingTemperature(temp)
                        }
                    }
                    break
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            guard let device = self.device(for: peripheral) else { return }
            if let error = error {
                self.addLog("알림 설정 오류: \(error.localizedDescription)", type: .error, device: device.name)
                return
            }
            for service in device.services {
                if let bleChar = service.characteristics.first(where: { $0.characteristic.uuid == characteristic.uuid }) {
                    bleChar.isNotifying = characteristic.isNotifying
                    let state = characteristic.isNotifying ? "활성화" : "비활성화"
                    self.addLog("알림 \(state): \(bleChar.displayName)", type: .info, device: device.name)
                    break
                }
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            guard let device = self.device(for: peripheral) else { return }
            if let error = error {
                self.addLog("쓰기 오류: \(error.localizedDescription)", type: .error, device: device.name)
            } else {
                self.addLog("쓰기 완료: \(BluetoothUUIDHelper.characteristicDisplayName(for: characteristic.uuid))", type: .info, device: device.name)
            }
        }
    }
}

// MARK: - Data Extension

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
