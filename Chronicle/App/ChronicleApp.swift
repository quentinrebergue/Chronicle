import SwiftUI

@main
struct ChronicleApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            RecordingView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
