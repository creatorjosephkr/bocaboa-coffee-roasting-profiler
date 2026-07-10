import Foundation

// MARK: - RoastSession (저장 가능한 세션 전체 데이터)

struct RoastSession: Codable, Identifiable {
    let id: UUID
    let date: Date
    var beanName: String
    var beanWeight: String
    var preheatTemp: String
    var targetDTR: String
    var events: [SavedEvent]
    var graphPoints: [SavedGraphPoint]
    var memo: String?

    // 계산된 결과값 (종료 시 기록)
    var finalDTR: Double?
    var totalRoastSeconds: Double?   // 투입 ~ 종료
    var devTimeSeconds: Double?      // 1차 팝 ~ 종료
    var chargeTemp: Double?          // 투입 온도
    var firstPopTemp: Double?        // 1차 팝 온도
    var finishTemp: Double?          // 배출 온도

    /// 파일명으로 쓸 포맷 (날짜_원두명)
    var suggestedFileName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        let dateStr = formatter.string(from: date)
        let safe = beanName.isEmpty ? "unnamed" : beanName.replacingOccurrences(of: " ", with: "_")
        return "\(dateStr)_\(safe).json"
    }

    /// 표시용 날짜 문자열
    var displayDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy.MM.dd HH:mm"
        return f.string(from: date)
    }
}

// MARK: - SavedEvent

struct SavedEvent: Codable, Identifiable {
    let id: UUID
    var elapsedSeconds: Double   // 예열 시작 기준 경과초
    let temperature: Double
    let heatValue: Int
    let type: String
    let description: String

    var formattedTime: String {
        let absSec = Int(abs(elapsedSeconds))
        let m = absSec / 60
        let s = absSec % 60
        let sign = elapsedSeconds < 0 ? "-" : ""
        return String(format: "%@%02d:%02d", sign, m, s)
    }
}

// MARK: - SavedGraphPoint

struct SavedGraphPoint: Codable, Identifiable {
    let id: UUID
    var relativeTime: Double   // 예열 시작 기준 경과초
    let temperature: Double
    let heat: Int
    var ror: Double?
}

// MARK: - Convenience init from live session data

extension RoastSession {
    init(
        beanName: String,
        beanWeight: String,
        preheatTemp: String,
        targetDTR: String,
        events: [BluetoothManager.RoastEvent],
        graphPoints: [BluetoothManager.RoastDataPoint]
    ) {
        self.id = UUID()
        self.date = Date()
        self.beanName = beanName
        self.beanWeight = beanWeight
        self.preheatTemp = preheatTemp
        self.targetDTR = targetDTR

        self.events = events.map {
            SavedEvent(
                id: $0.id,
                elapsedSeconds: $0.elapsedSeconds,
                temperature: $0.temperature,
                heatValue: $0.heatValue,
                type: $0.type,
                description: $0.description
            )
        }

        self.graphPoints = graphPoints.map {
            SavedGraphPoint(id: $0.id, relativeTime: $0.relativeTime,
                            temperature: $0.temperature, heat: $0.heat, ror: $0.ror)
        }

        // 계산값 추출
        let chargeEvent  = events.first { $0.type == "투입" }
        let firstPop     = events.first { $0.type == "1차 팝" }
        let finishEvent  = events.first { $0.type == "종료" }

        chargeTemp   = chargeEvent?.temperature
        firstPopTemp = firstPop?.temperature
        finishTemp   = finishEvent?.temperature

        if let charge = chargeEvent, let finish = finishEvent {
            totalRoastSeconds = finish.elapsedSeconds - charge.elapsedSeconds
        }
        if let pop = firstPop, let finish = finishEvent {
            devTimeSeconds = finish.elapsedSeconds - pop.elapsedSeconds
        }
        if let total = totalRoastSeconds, let dev = devTimeSeconds, total > 0 {
            finalDTR = (dev / total) * 100.0
        }
    }
}
