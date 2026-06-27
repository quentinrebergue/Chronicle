import Foundation

enum ToolDefinitions {
    static let all: [[String: any Sendable]] = [
        createPerson,
        createEvent,
        createPlace,
        setEmotion
    ]

    static let createPerson: [String: any Sendable] = [
        "type": "function",
        "function": [
            "name": "createPerson",
            "description": "Crée ou met à jour une personne mentionnée dans l'entrée vocale",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Prénom ou nom de la personne"
                    ] as [String: any Sendable],
                    "relation": [
                        "type": "string",
                        "description": "Relation avec l'utilisateur (ami, collègue, famille, médecin, etc.)"
                    ] as [String: any Sendable],
                    "sentiment": [
                        "type": "string",
                        "enum": ["positif", "neutre", "négatif"],
                        "description": "Sentiment général associé à cette personne dans le contexte"
                    ] as [String: any Sendable]
                ] as [String: any Sendable],
                "required": ["name"]
            ] as [String: any Sendable]
        ] as [String: any Sendable]
    ]

    static let createEvent: [String: any Sendable] = [
        "type": "function",
        "function": [
            "name": "createEvent",
            "description": "Crée un événement mentionné dans l'entrée vocale",
            "parameters": [
                "type": "object",
                "properties": [
                    "title": [
                        "type": "string",
                        "description": "Titre court de l'événement"
                    ] as [String: any Sendable],
                    "date": [
                        "type": "string",
                        "description": "Date de l'événement au format YYYY-MM-DD si mentionnée"
                    ] as [String: any Sendable],
                    "importance": [
                        "type": "integer",
                        "description": "Importance de 1 (faible) à 5 (majeur)"
                    ] as [String: any Sendable],
                    "emotion": [
                        "type": "string",
                        "description": "Émotion principale associée (joie, tristesse, anxiété, fierté, colère, etc.)"
                    ] as [String: any Sendable]
                ] as [String: any Sendable],
                "required": ["title"]
            ] as [String: any Sendable]
        ] as [String: any Sendable]
    ]

    static let createPlace: [String: any Sendable] = [
        "type": "function",
        "function": [
            "name": "createPlace",
            "description": "Crée un lieu mentionné dans l'entrée vocale",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Nom du lieu"
                    ] as [String: any Sendable],
                    "context": [
                        "type": "string",
                        "description": "Contexte associé au lieu (retrouvailles, travail, vacances, etc.)"
                    ] as [String: any Sendable]
                ] as [String: any Sendable],
                "required": ["name"]
            ] as [String: any Sendable]
        ] as [String: any Sendable]
    ]

    static let setEmotion: [String: any Sendable] = [
        "type": "function",
        "function": [
            "name": "setEmotion",
            "description": "Définit l'émotion dominante de l'entrée vocale",
            "parameters": [
                "type": "object",
                "properties": [
                    "emotion": [
                        "type": "string",
                        "description": "Émotion dominante (joie, tristesse, anxiété, fierté, colère, sérénité, nostalgie, etc.)"
                    ] as [String: any Sendable],
                    "intensity": [
                        "type": "integer",
                        "description": "Intensité de 1 (légère) à 5 (très forte)"
                    ] as [String: any Sendable]
                ] as [String: any Sendable],
                "required": ["emotion"]
            ] as [String: any Sendable]
        ] as [String: any Sendable]
    ]
}
