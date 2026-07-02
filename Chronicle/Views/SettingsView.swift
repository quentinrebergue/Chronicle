import SwiftUI

struct SettingsView: View {
    var onMenuTap: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OtobioTopBar(title: "Paramètres", onMenuTap: onMenuTap)

                List {
                    Section {
                        NavigationLink {
                            EntitiesView()
                        } label: {
                            Label("Personnes & lieux", systemImage: "person.text.rectangle")
                        }
                    } header: {
                        Text("Contenu")
                    }

                    Section {
                        Label("Rappels hebdo, mensuels et annuels activés", systemImage: "bell")
                            .foregroundStyle(Otobio.textSecondary)
                    } header: {
                        Text("Notifications")
                    } footer: {
                        Text("Gère la permission depuis Réglages iOS > Otobio > Notifications.")
                    }

                    #if DEBUG
                    Section {
                        NavigationLink {
                            DebugSeedView()
                        } label: {
                            Label("Injecter du contenu de test", systemImage: "wand.and.stars")
                        }
                    } header: {
                        Text("Développement")
                    } footer: {
                        Text("Visible uniquement en build debug — génère de fausses entrées avec des dates rétroactives pour tester les récits hebdo/mensuel/annuel.")
                    }
                    #endif

                    Section {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text(appVersion)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Otobio.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
