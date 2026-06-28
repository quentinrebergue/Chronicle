import SwiftUI

enum Otobio {
    // MARK: - Adaptive Colors (programmatic light/dark)

    static var background: Color {
        Color(light: .init(hex: "F5F0E8"), dark: .init(hex: "171310"))
    }

    static var cardBackground: Color {
        Color(light: .init(hex: "EFE7D6"), dark: .init(hex: "211C17"))
    }

    static var textPrimary: Color {
        Color(light: .init(hex: "1E1914"), dark: .init(hex: "EBE5DB"))
    }

    static var textSecondary: Color {
        Color(light: .init(hex: "6B5C4A"), dark: .init(hex: "9E9489"))
    }

    static var textTertiary: Color {
        Color(light: .init(hex: "948573"), dark: .init(hex: "736B5F"))
    }

    static var brand: Color {
        Color(light: .init(hex: "3D1C0A"), dark: .init(hex: "C79972"))
    }

    static var brandLight: Color {
        Color(light: .init(hex: "C4A882"), dark: .init(hex: "594733"))
    }

    static var separator: Color {
        Color(light: .init(hex: "C4A882"), dark: .init(hex: "383028"))
    }

    // Entity colors
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

    // MARK: - Entity helpers

    static func entityColor(for type: DetectedEntity.EntityType) -> Color {
        switch type {
        case .place: entityPlace
        case .person: entityPerson
        case .event: entityEvent
        case .activity: entityActivity
        case .organization: textSecondary
        }
    }

    static func entityIcon(for type: DetectedEntity.EntityType) -> String {
        switch type {
        case .place: "mappin"
        case .person: "person"
        case .event: "star"
        case .activity: "figure.run"
        case .organization: "building.2"
        }
    }
}

// MARK: - Color extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
