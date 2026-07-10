import Foundation
import CoreBluetooth
import SwiftUI

// MARK: - BLEService

final class BLEService: Identifiable, ObservableObject {
    let id: String
    let service: CBService
    @Published var characteristics: [BLECharacteristic] = []
    @Published var isExpanded: Bool = true

    var uuid: String { service.uuid.uuidString }
    var isPrimary: Bool { service.isPrimary }

    var knownName: String? { BluetoothUUIDHelper.serviceName(for: service.uuid) }
    var isStandard: Bool   { knownName != nil }

    var displayName: String {
        knownName ?? "Custom Service"
    }

    var shortUUID: String {
        let s = service.uuid.uuidString.uppercased()
        if s.count == 36 {
            // Full UUID: take the first part (e.g. 0000180D → 180D)
            let startIdx = s.index(s.startIndex, offsetBy: 4)
            let endIdx   = s.index(s.startIndex, offsetBy: 8)
            let short = String(s[startIdx..<endIdx])
            // If it starts with "0000", drop zeros
            return short.hasPrefix("0000") ? String(short.dropFirst(4)) : short
        }
        return s
    }

    init(service: CBService) {
        self.id      = service.uuid.uuidString
        self.service = service
    }
}
