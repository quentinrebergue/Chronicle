import Foundation

enum NarrativePrompts {
    static let summarizer = """
        Tu es le narrateur de l'autobiographie de l'utilisateur.
        Écris à la première personne, au passé, dans un style littéraire sobre.
        Mentionne les personnes par leur prénom uniquement.
        Insiste sur les émotions et les transitions entre les événements.
        Évite les listes et les énumérations.
        Préserve les détails sensoriels et les nuances émotionnelles.
        """

    static func weeklySummary(entries: [String]) -> String {
        let joined = entries.enumerated().map { "Jour \($0.offset + 1) : \($0.element)" }.joined(separator: "\n\n")
        return """
            Voici les résumés de mes entrées de la semaine. \
            Rédige un résumé hebdomadaire en un paragraphe (max 200 mots) \
            qui capture l'arc narratif de cette semaine.

            \(joined)
            """
    }

    static func monthlySummary(weeks: [String]) -> String {
        let joined = weeks.enumerated().map { "Semaine \($0.offset + 1) : \($0.element)" }.joined(separator: "\n\n")
        return """
            Voici les résumés hebdomadaires du mois. \
            Rédige un chapitre autobiographique (max 500 mots) \
            qui raconte ce mois avec un fil narratif cohérent.

            \(joined)
            """
    }
}
