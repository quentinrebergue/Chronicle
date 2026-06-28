import SwiftUI

struct MainTabView: View {
    @ObservedObject var llmService: LLMService

    var body: some View {
        TabView {
            HistoryView()
                .tabItem {
                    Label("Bibliothèque", systemImage: "book")
                }

            RecordingView(llmService: llmService)
                .tabItem {
                    Label("Enregistrer", systemImage: "mic.fill")
                }

            EntitiesView()
                .tabItem {
                    Label("Entités", systemImage: "person.text.rectangle")
                }
        }
        .tint(Otobio.marronFonce)
    }
}
