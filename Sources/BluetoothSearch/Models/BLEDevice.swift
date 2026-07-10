import Foundation
import CoreBluetooth
import SwiftUI

// MARK: - Connection Status

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(String)

    var label: String {
        switch self {
        case .disconnected:   return "연결 안됨"
        case .connecting:     return "연결 중..."
        case .connected:      return "연결됨"
        case .failed(let msg): return "실패: \(msg)"
        }
    }

    var shortLabel: String {
        switch self {
        case .disconnected: return "미연결"
        case .connecting:   return "연결 중"
        case .connected:    return "연결됨"
        case .failed:       return "실패"
        }
    }

    var color: Color {
        switch self {
        case .disconnected: return .textTertiary
        case .connecting:   return .appWarning
        case .connected:    return .appSuccess
        case .failed:       return .appError
        }
    }

    var icon: String {
        switch self {
        case .disconnected: return "circle"
        case .connecting:   return "arrow.triangle.2.circlepath"
        case .connected:    return "checkmark.circle.fill"
        case .failed:       return "xmark.circle.fill"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected): return true
        case (.connecting, .connecting):     return true
        case (.connected, .connected):       return true
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - BLEDevice

final class BLEDevice: Identifiable, ObservableObject {
    let id: UUID
    let peripheral: CBPeripheral

    @Published var name: String
    @Published var rssi: Int
    @Published var advertisementData: [String: Any]
    @Published var status: ConnectionStatus = .disconnected
    @Published var services: [BLEService] = []
    @Published var lastSeen: Date = Date()

    // MARK: Computed Properties

    var peripheralUUID: String { peripheral.identifier.uuidString }

    var manufacturerData: Data? {
        advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
    }

    var manufacturerDataHex: String {
        guard let data = manufacturerData else { return "-" }
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var advertisedServiceUUIDs: [CBUUID] {
        advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
    }

    var advertisedServiceNames: [String] {
        advertisedServiceUUIDs.map { BluetoothUUIDHelper.serviceDisplayName(for: $0) }
    }

    var isConnectable: Bool {
        advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? true
    }

    var txPowerLevel: Int? {
        advertisementData[CBAdvertisementDataTxPowerLevelKey] as? Int
    }

    // MARK: RSSI Helpers

    var rssiStrength: Int {
        switch rssi {
        case ..<(-90): return 0
        case -90 ..< -75: return 1
        case -75 ..< -60: return 2
        case -60 ..< -45: return 3
        default: return 4
        }
    }

    var rssiColor: Color {
        switch rssiStrength {
        case 0:  return .appError
        case 1:  return .appWarning
        case 2:  return Color(hex: "#FFD60A")
        case 3:  return .appAccent
        default: return .appSuccess
        }
    }

    var rssiDescription: String {
        switch rssiStrength {
        case 0:  return "매우 약함"
        case 1:  return "약함"
        case 2:  return "보통"
        case 3:  return "강함"
        default: return "매우 강함"
        }
    }

    // MARK: Init

    init(peripheral: CBPeripheral, rssi: Int, advertisementData: [String: Any]) {
        self.id              = peripheral.identifier
        self.peripheral      = peripheral
        self.rssi            = rssi
        self.advertisementData = advertisementData
        // Prefer local name from advertisement, then peripheral.name
        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        self.name = localName ?? peripheral.name ?? "알 수 없는 기기"
    }
}
