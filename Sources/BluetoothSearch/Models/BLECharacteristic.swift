import Foundation
import CoreBluetooth
import SwiftUI

// MARK: - Characteristic Property

enum CharacteristicProperty: String, CaseIterable {
    case broadcast         = "BROADCAST"
    case read              = "READ"
    case writeNoResponse   = "WRITE NR"
    case write             = "WRITE"
    case notify            = "NOTIFY"
    case indicate          = "INDICATE"
    case signedWrite       = "AUTH"
    case extendedProps     = "EXT"

    var color: Color {
        switch self {
        case .read:          return .appAccent
        case .write:         return .appWarning
        case .writeNoResponse: return Color(hex: "#FF6B35")
        case .notify:        return .appSuccess
        case .indicate:      return .appDiscovered
        case .broadcast:     return Color(hex: "#FFD60A")
        case .signedWrite:   return Color(hex: "#FF375F")
        case .extendedProps: return .textSecondary
        }
    }
}

// MARK: - Data Display Format

enum DataDisplayFormat: String, CaseIterable {
    case hex     = "HEX"
    case ascii   = "ASCII"
    case decimal = "DEC"
    case binary  = "BIN"
}

// MARK: - BLECharacteristic

final class BLECharacteristic: Identifiable, ObservableObject {
    let id: String
    let characteristic: CBCharacteristic
    @Published var value: Data?
    @Published var isNotifying: Bool
    @Published var lastUpdated: Date?
    @Published var updateCount: Int = 0

    var uuid: String { characteristic.uuid.uuidString }

    var knownName: String? { BluetoothUUIDHelper.characteristicName(for: characteristic.uuid) }
    var displayName: String { knownName ?? "Characteristic" }

    var shortUUID: String {
        let s = characteristic.uuid.uuidString.uppercased()
        if s.count == 36 {
            let startIdx = s.index(s.startIndex, offsetBy: 4)
            let endIdx   = s.index(s.startIndex, offsetBy: 8)
            let short = String(s[startIdx..<endIdx])
            return short.hasPrefix("0000") ? String(short.dropFirst(4)) : short
        }
        return s
    }

    // MARK: Properties

    var properties: [CharacteristicProperty] {
        var props: [CharacteristicProperty] = []
        let p = characteristic.properties
        if p.contains(.broadcast)          { props.append(.broadcast) }
        if p.contains(.read)               { props.append(.read) }
        if p.contains(.writeWithoutResponse) { props.append(.writeNoResponse) }
        if p.contains(.write)              { props.append(.write) }
        if p.contains(.notify)             { props.append(.notify) }
        if p.contains(.indicate)           { props.append(.indicate) }
        if p.contains(.authenticatedSignedWrites) { props.append(.signedWrite) }
        if p.contains(.extendedProperties) { props.append(.extendedProps) }
        return props
    }

    var canRead:   Bool { characteristic.properties.contains(.read) }
    var canWrite:  Bool { characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) }
    var canNotify: Bool { characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) }

    // MARK: Value Formatting

    func formattedValue(as format: DataDisplayFormat) -> String {
        guard let data = value, !data.isEmpty else { return "—" }
        switch format {
        case .hex:
            return data.map { String(format: "%02X", $0) }.joined(separator: " ")
        case .ascii:
            if let s = String(data: data, encoding: .utf8)  { return s }
            if let s = String(data: data, encoding: .ascii) { return s }
            return data.map { String(format: "%02X", $0) }.joined(separator: " ")
        case .decimal:
            return data.map { String($0) }.joined(separator: " ")
        case .binary:
            return data.map { String($0, radix: 2).leftPadded(toLength: 8, with: "0") }.joined(separator: " ")
        }
    }

    var hexValue: String     { formattedValue(as: .hex) }
    var asciiValue: String   { formattedValue(as: .ascii) }
    var decimalValue: String { formattedValue(as: .decimal) }
    var byteCount: Int       { value?.count ?? 0 }

    // MARK: Init

    init(characteristic: CBCharacteristic) {
        self.id            = characteristic.uuid.uuidString
        self.characteristic = characteristic
        self.isNotifying   = characteristic.isNotifying
        self.value         = characteristic.value
    }
}

// MARK: - String Padding Helper

private extension String {
    func leftPadded(toLength length: Int, with character: Character) -> String {
        if self.count >= length { return self }
        return String(repeating: character, count: length - self.count) + self
    }
}
