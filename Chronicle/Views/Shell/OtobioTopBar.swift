import SwiftUI

/// Barre supérieure custom — remplace la navigation bar Apple par défaut.
struct OtobioTopBar: View {
    let title: String
    var isBrandTitle = false
    var onMenuTap: () -> Void
    var trailingIcon: String? = nil
    var onTrailingTap: (() -> Void)? = nil

    var body: some View {
        HStack {
            iconButton(systemName: "line.3.horizontal", action: onMenuTap)

            Spacer()

            Text(title)
                .font(isBrandTitle ? Otobio.brandTitle(20) : Otobio.uiTitle(17))
                .foregroundStyle(Otobio.brand)

            Spacer()

            if let trailingIcon, let onTrailingTap {
                iconButton(systemName: trailingIcon, action: onTrailingTap)
            } else {
                Color.clear.frame(width: 42, height: 42)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
        // Fondu du haut de l'écran vers le contenu : la barre se détache
        // du scroll qui passe dessous, sans ligne de séparation dure.
        .background(alignment: .top) {
            LinearGradient(
                colors: [Otobio.background, Otobio.background, Otobio.background.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 96)
            .allowsHitTesting(false)
        }
    }

    private func iconButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Otobio.textPrimary)
                .frame(width: 42, height: 42)
                .background(Otobio.cardBackground)
                .clipShape(Circle())
        }
    }
}
