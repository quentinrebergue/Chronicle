import SwiftUI

@main
struct ChronicleApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var llmService = LLMService()

    var body: some Scene {
        WindowGroup {
            RecordingView(llmService: llmService)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .task {
                    do {
                        try await llmService.downloadModel()
                    } catch {
                        print("⚠️ Téléchargement modèle: \(error)")
                    }
                }
        }
    }
}
