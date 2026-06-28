import SwiftUI

enum Otobio {
    // MARK: - Colors
    static let parchemin = Color(hex: "F5F0E8")
    static let cremeAncien = Color(hex: "EDE5D4")
    static let marronFonce = Color(hex: "3D1C0A")
    static let marronChaud = Color(hex: "6B3520")
    static let beigeDoré = Color(hex: "C4A882")
    static let marronNuit = Color(hex: "1F0A02")
    static let accent = Color(hex: "9C6B4A")

    // MARK: - Entity colors (warm palette)
    static let entityPerson = Color(hex: "6B3520")
    static let entityPlace = Color(hex: "3D6B5A")
    static let entityEvent = Color(hex: "8B6914")
    static let entityActivity = Color(hex: "5A3D6B")

    // MARK: - Fonts
    static func brandTitle(_ size: CGFloat = 28) -> Font {
        .custom("TimesNewRomanPS-ItalicMT", size: size)
    }

    static func sectionTitle(_ size: CGFloat = 20) -> Font {
        .custom("TimesNewRomanPSMT", size: size)
    }

    static func bodyText(_ size: CGFloat = 16) -> Font {
        .system(size: size)
    }

    static func label(_ size: CGFloat = 13) -> Font {
        .system(size: size)
    }

    static func micro(_ size: CGFloat = 11) -> Font {
        .system(size: size)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}
