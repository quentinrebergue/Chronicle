import Foundation

enum NarrativePrompts {
    static let summarizer = """
        Tu es le narrateur de l'autobiographie de l'utilisateur.
        Écris à la première personne, au passé.
        Style naturel et fluide, comme un journal intime bien écrit. Pas de métaphores, pas de poésie.
        Mentionne les personnes par leur prénom uniquement.
        Relie les événements entre eux avec des transitions naturelles.
        Évite les listes et les énumérations.
        Réponds directement avec le texte narratif, sans explication ni réflexion.
        """

    static func dailySummary(card: String) -> String {
        """
        Voici les données structurées d'une entrée de journal vocal. \
        Rédige un résumé narratif à la première personne, au passé (5-8 phrases, ~100-150 mots). \
        Style naturel comme un journal intime, pas de poésie ni de métaphores. \
        Raconte la journée avec fluidité en reliant les moments entre eux.

        \(card)
        """
    }

    static func dailyTitle(summary: String) -> String {
        """
        Voici le résumé d'une entrée de journal intime. \
        Trouve un titre très bref (2 à 5 mots, sans ponctuation finale) qui capture l'essentiel de cette journée. \
        Réponds uniquement avec le titre, rien d'autre.

        \(summary)
        """
    }

    static func weeklySummary(entries: [String], facts: String = "") -> String {
        let joined = entries.enumerated().map { "Jour \($0.offset + 1) : \($0.element)" }.joined(separator: "\n\n")
        let factsBlock = facts.isEmpty ? "" : """

            Faits de la semaine (utilise-les pour être précis, sans les énumérer) :
            \(facts)
            """
        return """
            Voici les résumés de mes entrées de la semaine. \
            Rédige un récit hebdomadaire (10-15 phrases, ~200-250 mots) \
            qui capture l'arc narratif de cette semaine. \
            Écris à la première personne, au passé, style naturel. \
            Relie les jours entre eux, souligne ce qui revient et ce qui change.
            \(factsBlock)
            \(joined)
            """
    }

    static func monthlySummary(weeks: [String]) -> String {
        let joined = weeks.enumerated().map { "Semaine \($0.offset + 1) : \($0.element)" }.joined(separator: "\n\n")
        return """
            Voici les résumés hebdomadaires du mois. \
            Rédige un chapitre autobiographique (max 500 mots) \
            qui raconte ce mois avec un fil narratif cohérent. \
            Écris à la première personne, au passé, style naturel et engageant.

            \(joined)
            """
    }

    static func yearlySummary(months: [String]) -> String {
        let joined = months.enumerated().map { "Mois \($0.offset + 1) : \($0.element)" }.joined(separator: "\n\n")
        return """
            Voici les chapitres mensuels de l'année. \
            Rédige un chapitre annuel autobiographique (max 1500 mots) \
            qui retrace cette année avec ses grands arcs narratifs, \
            ses tournants et son évolution personnelle. \
            Écris à la première personne, au passé, style naturel et engageant.

            \(joined)
            """
    }
}
