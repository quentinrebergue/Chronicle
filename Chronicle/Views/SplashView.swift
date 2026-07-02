import SwiftUI

/// Écran de démarrage — juste le logo, le temps que la vérification du modèle
/// et les tâches de lancement se terminent. Évite de montrer l'app à moitié prête.
struct SplashView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Otobio.background.ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Otobio")
                    .font(Otobio.brandTitle(40))
                    .foregroundStyle(Otobio.brand)
                    .opacity(pulse ? 1 : 0.6)

                ProgressView()
                    .tint(Otobio.brand)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

#Preview {
    SplashView()
}
