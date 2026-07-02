import SwiftUI

/// Coquille de l'app : contenu principal + tiroir latéral (inspiré de Claude).
/// Remplace la TabView Apple par défaut par une navigation plus sobre.
struct AppShell: View {
    @ObservedObject var llmService: LLMService
    /// Capturés par RootView avant tout ignoresSafeArea() — un GeometryReader logé
    /// ici même, sous le ignoresSafeArea appliqué plus bas, rapporterait des insets à zéro.
    let safeInsets: EdgeInsets

    enum Destination {
        case recording, autobiographie, journal, settings
    }

    @State private var destination: Destination = .recording
    @State private var isMenuOpen = false

    private let menuWidth: CGFloat = 260

    var body: some View {
        GeometryReader { geo in
            let insets = safeInsets
            let totalWidth = geo.size.width
            let totalHeight = geo.size.height

            ZStack(alignment: .leading) {
                // Le menu est dessiné DERRIÈRE la carte : l'ombre de celle-ci tombe dessus.
                SideMenuView(destination: $destination) { dest in
                    destination = dest
                    close()
                }
                .frame(width: menuWidth, height: totalHeight)
                .padding(.top, insets.top)
                .padding(.bottom, insets.bottom)
                .opacity(isMenuOpen ? 1 : 0)
                .allowsHitTesting(isMenuOpen)

                content
                    .padding(.top, insets.top)
                    .padding(.bottom, insets.bottom)
                    // Taille fixe (pas .infinity) : la zone de fermeture ci-dessous peut alors
                    // être positionnée à des coordonnées exactes qui ne chevauchent jamais le menu,
                    // peu importe les subtilités du hit-testing avec offset/clipShape/shadow.
                    .frame(width: totalWidth, height: totalHeight)
                    .background(Otobio.background)
                    .clipShape(RoundedRectangle(cornerRadius: isMenuOpen ? 24 : 0, style: .continuous))
                    .shadow(color: Otobio.overlayScrim.opacity(isMenuOpen ? 0.25 : 0), radius: 20, x: -4, y: 0)
                    .offset(x: isMenuOpen ? menuWidth : 0)
                    .allowsHitTesting(!isMenuOpen)

                // Zone de fermeture : rectangle explicite calé exactement sur la portion
                // visible du contenu décalé — géométriquement impossible de recouvrir le menu.
                if isMenuOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: totalWidth - menuWidth, height: totalHeight)
                        .position(x: menuWidth + (totalWidth - menuWidth) / 2, y: totalHeight / 2)
                        .onTapGesture { close() }
                }
            }
            .frame(width: totalWidth, height: totalHeight)
        }
        .background(Otobio.background.ignoresSafeArea())
        .ignoresSafeArea()
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isMenuOpen)
        .simultaneousGesture(edgeSwipeGesture)
        .onReceive(NotificationCenter.default.publisher(for: NotificationService.openLibraryNotification)) { _ in
            destination = .autobiographie
        }
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .recording:
            RecordingView(llmService: llmService, onMenuTap: toggle)
        case .autobiographie:
            HistoryView(llmService: llmService, onMenuTap: toggle)
        case .journal:
            JournalView(onMenuTap: toggle)
        case .settings:
            SettingsView(onMenuTap: toggle)
        }
    }

    private func toggle() {
        isMenuOpen.toggle()
    }

    private func close() {
        isMenuOpen = false
    }

    /// Glisser vers la droite n'importe où pour ouvrir, vers la gauche pour fermer.
    private var edgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                let isMostlyHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                guard isMostlyHorizontal else { return }

                if !isMenuOpen && value.translation.width > 40 {
                    isMenuOpen = true
                } else if isMenuOpen && value.translation.width < -40 {
                    isMenuOpen = false
                }
            }
    }
}
