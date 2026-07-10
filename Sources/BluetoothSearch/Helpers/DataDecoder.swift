import Foundation

// MARK: - Temperature Entry

struct TemperatureEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let celsius: Double
    let deviceName: String

    var fahrenheit: Double { celsius * 9 / 5 + 32 }

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: timestamp)
    }
}

// MARK: - Decoded Packet

struct DecodedPacket {
    enum PacketType {
        case bocaTemperature(celsius: Double)
        case unknown
    }
    let type: PacketType
    let formatDescription: String
    let fieldDescriptions: [(offset: Int, length: Int, label: String, value: String)]
}

// MARK: - Data Decoder

struct DataDecoder {

    /// 수신된 raw Data를 분석하여 알려진 프로토콜 패킷으로 디코딩합니다.
    static func decode(_ data: Data) -> DecodedPacket? {
        if let boca = decodeBocaPacket(data) { return boca }
        return nil
    }

    // MARK: - BOCA Vocaboca Protocol
    //
    // 패킷 구조 (10 bytes):
    //   [0]    FE  - Start of Frame 1
    //   [1]    EF  - Start of Frame 2
    //   [2]    01  - Protocol version
    //   [3]    01  - Message type (0x01 = sensor data)
    //   [4]    HH  - Temperature raw value (high byte, big-endian uint16)
    //   [5]    LL  - Temperature raw value (low byte)
    //   [6]    00  - Reserved 1
    //   [7]    00  - Reserved 2
    //   [8]    EF  - End of Frame 1
    //   [9]    FE  - End of Frame 2
    //
    // 온도 변환 공식:
    //   raw    = uint16(data[4]) << 8 | uint16(data[5])   (big-endian)
    //   temp°C = (raw - 42.0) / 32.0
    //
    // 예시:
    //   raw=256 (0x0100) → (256 - 42)/32  = 6.6875°C (약 6.7°C, 얼음물 실측치)
    //   raw=1112(0x0458) → (1112 - 42)/32 = 33.4375°C(약 33.4°C, 손 움켜쥠 실측치)
    //   raw=848 (0x0350) → (848 - 42)/32  = 25.1875°C(약 25.2°C, 여름 실내 온도)

    static func decodeBocaPacket(_ data: Data) -> DecodedPacket? {
        guard data.count == 10,
              data[0] == 0xFE, data[1] == 0xEF,
              data[8] == 0xEF, data[9] == 0xFE
        else { return nil }

        let rawValue = (UInt16(data[4]) << 8) | UInt16(data[5])
        let tempCelsius = (Double(rawValue) - 42.0) / 32.0

        let batteryEst = extractBatteryLevel(data)
        let batteryStr = batteryEst != nil ? "\(batteryEst!)%" : "00 00 (미수신/0%)"

        let fields: [(Int, Int, String, String)] = [
            (0, 2, "Start of Frame",   "FE EF"),
            (2, 1, "Protocol Version", String(format: "%02X", data[2])),
            (3, 1, "Message Type",     String(format: "%02X (센서 데이터)", data[3])),
            (4, 2, "Temperature raw",  String(format: "%02X %02X → uint16=%d", data[4], data[5], rawValue)),
            (6, 2, "Battery (배터리 추정)", String(format: "%02X %02X → %@", data[6], data[7], batteryStr)),
            (8, 2, "End of Frame",     "EF FE"),
        ]

        return DecodedPacket(
            type: .bocaTemperature(celsius: tempCelsius),
            formatDescription: "BOCA Vocaboca SPP 온도 프로토콜",
            fieldDescriptions: fields
        )
    }

    /// BOCA 패킷에서 배터리 레벨(%) 추출 (추정치)
    /// 6번 바이트를 배터리 퍼센트로 간주. (0~100 범위)
    /// 6, 7번 바이트가 모두 0이면 미수신 상태(nil)로 처리
    static func extractBatteryLevel(_ data: Data) -> Int? {
        guard isBocaTemperaturePacket(data) else { return nil }
        if data[6] == 0 && data[7] == 0 {
            return nil
        }
        let batteryVal = Int(data[6])
        if batteryVal >= 0 && batteryVal <= 100 {
            return batteryVal
        }
        return nil
    }

    /// 이 데이터가 BOCA 온도 패킷인지 빠르게 확인
    static func isBocaTemperaturePacket(_ data: Data) -> Bool {
        data.count == 10 &&
        data[0] == 0xFE && data[1] == 0xEF &&
        data[8] == 0xEF && data[9] == 0xFE
    }

    /// BOCA 패킷에서 온도 값 추출 (nil = 비해당 패킷)
    /// 공식: temp_C = (uint16_BE(byte4, byte5) - 42.0) / 32.0
    static func extractTemperature(_ data: Data) -> Double? {
        guard isBocaTemperaturePacket(data) else { return nil }
        let rawValue = (UInt16(data[4]) << 8) | UInt16(data[5])
        return (Double(rawValue) - 42.0) / 32.0
    }
}
