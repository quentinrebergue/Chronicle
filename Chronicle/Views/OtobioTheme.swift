import SwiftUI

enum Otobio {
    // MARK: - Adaptive Colors (programmatic light/dark)

    static var background: Color {
        Color(light: .init(hex: "F5F0E8"), dark: .init(hex: "171310"))
    }

    static var cardBackground: Color {
        Color(light: .init(hex: "EFE7D6"), dark: .init(hex: "211C17"))
    }

    /// Cartes de récits — blanc pur pour se détacher du fond blanc cassé.
    static var recitCardBackground: Color {
        Color(light: .white, dark: .init(hex: "211C17"))
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

    // Semantic colors
    static let destructive = Color(hex: "C0392B")
    static let onDestructive = Color.white
    static let overlayScrim = Color.black
    static let success = Color(hex: "4A7A5A")
    static let warning = Color(hex: "B07D2E")

    // MARK: - Fonts

    /// Italique serif — réservé au logo "Otobio". Ne pas utiliser pour l'UI.
    static func brandTitle(_ size: CGFloat = 28) -> Font {
        .custom("TimesNewRomanPS-ItalicMT", size: size)
    }

    /// Serif regular — pour les titres de contenu narratif (chapitres, récits).
    static func serifTitle(_ size: CGFloat = 22) -> Font {
        .custom("TimesNewRomanPSMT", size: size)
    }

    /// Serif regular — pour le corps du texte narratif (la prose des récits).
    static func serifBody(_ size: CGFloat = 16) -> Font {
        .custom("TimesNewRomanPSMT", size: size)
    }

    /// Titres d'interface — SF Pro semibold, sobre et sérieux.
    static func uiTitle(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold)
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

    // MARK: - Elevation

    static var cardShadow: Color {
        Color(light: .init(hex: "3D1C0A").opacity(0.08), dark: .black.opacity(0.35))
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

// MARK: - Card style

struct OtobioCardStyle: ViewModifier {
    var padding: CGFloat = 16
    var radius: CGFloat = 16
    var background: Color = Otobio.cardBackground

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Otobio.cardShadow, radius: 10, x: 0, y: 4)
    }
}

extension View {
    func otobioCard(padding: CGFloat = 16, radius: CGFloat = 16, background: Color = Otobio.cardBackground) -> some View {
        modifier(OtobioCardStyle(padding: padding, radius: radius, background: background))
    }
}

// MARK: - Skeleton loading

/// Barre scintillante pour les contenus en cours de génération.
struct SkeletonBar: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12

    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(Otobio.separator.opacity(0.3))
            .frame(width: width, height: height)
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.55), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.6)
                }
                .clipShape(RoundedRectangle(cornerRadius: height / 2))
            )
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

// MARK: - Phrases de progression (façon agent IA)

/// Pools de phrases par étape — donnent une idée de l'avancée réelle sans promettre une durée.
enum GenerationPhrase {
    static let loadingModel = [
        "Je réveille l'IA…", "Je charge le modèle…", "Encore un instant…",
        "Je prépare la mémoire…", "Presque prêt…"
    ]
    static let transcribing = [
        "J'écoute ta voix…", "Je transcris tes mots…", "Je capture chaque phrase…",
        "Je nettoie la transcription…"
    ]
    static let extracting = [
        "Je repère les personnes et les lieux…", "J'identifie ce qui compte…",
        "Je relie les événements entre eux…"
    ]
    static let verifying = [
        "Je vérifie les détails…", "Je relis pour être sûr…", "Je recoupe les informations…"
    ]
    static let dailySummary = [
        "Je relis ta journée…", "Je choisis les mots justes…",
        "Je mets de l'ordre dans tes idées…", "Je trouve le ton juste…"
    ]
    static let organizingFacts = [
        "J'organise les faits de la semaine…", "Je rassemble les personnes et les lieux…",
        "Je compte ce qui est revenu cette semaine…"
    ]
    static let weeklyWriting = [
        "Je relis ta semaine…", "Je cherche le fil…", "J'écris ton récit…",
        "Je relie tes journées entre elles…", "Je peaufine les transitions…"
    ]
    static let monthlyReading = [
        "Je relis tes semaines…", "Je repère les grands moments du mois…"
    ]
    static let monthlyWriting = [
        "Je façonne le chapitre…", "J'écris ton mois…", "Je relie tes semaines entre elles…",
        "Je trouve l'arc du mois…"
    ]
    static let yearlyReading = [
        "Je relis ton année…", "Je repère les grands tournants…"
    ]
    static let yearlyWriting = [
        "Je retrace le fil…", "J'écris ton grand chapitre…", "Je relie tes mois entre eux…",
        "Je prends du recul sur ton année…"
    ]

    /// Devine le pool à partir du statut brut émis par NarrativeService —
    /// chaque étape de la pipeline a sa propre voix, pour situer le user dans le processus.
    static func forStatus(_ status: String) -> [String] {
        if status.contains("Chargement") { return loadingModel }
        if status.contains("Résumé du jour") { return dailySummary }
        if status.contains("faits de la semaine") { return organizingFacts }
        if status.contains("récit de la semaine") { return weeklyWriting }
        if status.contains("chapitre de l'année") { return yearlyWriting }
        if status.contains("mois…") { return yearlyReading }
        if status.contains("semaines…") { return monthlyReading }
        if status.contains("chapitre") { return monthlyWriting }
        return loadingModel
    }
}

/// Affiche une phrase qui laisse place à la suivante en fondu, en boucle sur un pool donné.
/// Change de pool (donc redémarre) quand `phrases` change — utiliser `.task(id:)` en interne
/// pour annuler proprement l'ancienne boucle.
struct RotatingStatusText: View {
    let phrases: [String]
    var font: Font = Otobio.micro()
    var color: Color = Otobio.textTertiary

    @State private var index = 0

    var body: some View {
        Text(phrases.isEmpty ? "" : phrases[index % phrases.count])
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .id(index)
            .transition(.opacity)
            .task(id: phrases) {
                index = 0
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    guard !Task.isCancelled else { break }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        index += 1
                    }
                }
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
