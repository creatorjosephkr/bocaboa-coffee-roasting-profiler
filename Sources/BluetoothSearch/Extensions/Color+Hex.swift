import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:  (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:  (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - App Color Palette
extension Color {
    static let appBackground   = Color(hex: "#F5F6F8")
    static let appSurface      = Color(hex: "#FFFFFF")
    static let appSurface2     = Color(hex: "#FAFAFC")
    static let appBorder       = Color(white: 0.0, opacity: 0.1)
    static let appAccent       = Color(hex: "#007AFF")
    static let appAccent2      = Color(hex: "#0056D2")
    static let appSuccess      = Color(hex: "#34C759")
    static let appWarning      = Color(hex: "#FF9500")
    static let appError        = Color(hex: "#FF3B30")
    static let appData         = Color(hex: "#B45309")
    static let appDiscovered   = Color(hex: "#AF52DE")
    static let textPrimary     = Color(hex: "#1C1C1E")
    static let textSecondary   = Color(hex: "#68686E")
    static let textTertiary    = Color(hex: "#8E8E93")
}
