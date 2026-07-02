import SwiftUI

@main
struct ChronicleApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var llmService = LLMService()

    var body: some Scene {
        WindowGroup {
            RootView(llmService: llmService)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

/// Bascule entre l'écran de démarrage et l'app une fois les tâches de lancement terminées.
private struct RootView: View {
    @ObservedObject var llmService: LLMService
    @State private var isReady = false

    var body: some View {
        // GeometryReader posé ICI, à la racine, AVANT tout ignoresSafeArea() en aval —
        // c'est le seul endroit où geo.safeAreaInsets est garanti correct dès le premier
        // rendu. Un GeometryReader logé plus bas dans un sous-arbre déjà ignoresSafeArea
        // rapporte des insets à zéro (c'est ce qui causait le header collé en haut).
        GeometryReader { geo in
            ZStack {
                if isReady {
                    AppShell(llmService: llmService, safeInsets: geo.safeAreaInsets)
                        .transition(.opacity)
                } else {
                    SplashView()
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .animation(.easeInOut(duration: 0.35), value: isReady)
        .task {
            AppLogger.log("🚀 App lancée")
            // Active le delegate (tap notification → Bibliothèque) et
            // replanifie les rappels si la permission est déjà accordée
            await NotificationService.shared.rescheduleIfAuthorized()
            do {
                try await llmService.downloadModel()
            } catch {
                AppLogger.log("⚠️ Téléchargement modèle: \(error)")
            }
            isReady = true
        }
    }
}
