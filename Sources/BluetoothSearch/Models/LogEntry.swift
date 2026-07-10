import Foundation
import SwiftUI

// MARK: - LogEntry Model

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let type: LogType
    let deviceName: String?

    enum LogType: String {
        case info       = "INFO"
        case warning    = "WARN"
        case error      = "ERR "
        case discovered = "SCAN"
        case connected  = "CONN"
        case data       = "DATA"

        var color: Color {
            switch self {
            case .info:       return .appAccent
            case .warning:    return .appWarning
            case .error:      return .appError
            case .discovered: return .appDiscovered
            case .connected:  return .appSuccess
            case .data:       return .appData
            }
        }

        var icon: String {
            switch self {
            case .info:       return "info.circle.fill"
            case .warning:    return "exclamationmark.triangle.fill"
            case .error:      return "xmark.circle.fill"
            case .discovered: return "antenna.radiowaves.left.and.right"
            case .connected:  return "link.circle.fill"
            case .data:       return "arrow.down.circle.fill"
            }
        }
    }

    init(message: String, type: LogType, deviceName: String? = nil) {
        self.timestamp  = Date()
        self.message    = message
        self.type       = type
        self.deviceName = deviceName
    }

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: timestamp)
    }
}
