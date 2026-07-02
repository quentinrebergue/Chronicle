import SwiftUI
import CoreData

struct SideMenuView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var destination: AppShell.Destination
    let onSelect: (AppShell.Destination) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(spacing: 4) {
                menuRow(icon: "mic", label: "Nouvel enregistrement", destination: .recording)
                menuRow(icon: "book.closed", label: "Autobiographie", destination: .autobiographie, showDot: hasDueRecits)
                menuRow(icon: "square.and.pencil", label: "Journal", destination: .journal)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer()

            Rectangle()
                .fill(Otobio.separator)
                .frame(height: 0.5)

            menuRow(icon: "gearshape", label: "Paramètres", destination: .settings)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Otobio.background)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Otobio")
                .font(Otobio.brandTitle(24))
                .foregroundStyle(Otobio.brand)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 8)
    }

    /// Récits générés en attente d'écriture — évalué à chaque rendu (requête légère,
    /// le menu n'est composé que quand il est visible ou sur le point de l'être).
    private var hasDueRecits: Bool {
        !RecitPlanner.dueRecits(context: viewContext).isEmpty
    }

    private func menuRow(icon: String, label: String, destination dest: AppShell.Destination, showDot: Bool = false) -> some View {
        Button {
            onSelect(dest)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 22)
                Text(label)
                    .font(Otobio.label(15))
                if showDot {
                    Circle()
                        .fill(Otobio.brand)
                        .frame(width: 7, height: 7)
                }
                Spacer()
            }
            .foregroundStyle(destination == dest ? Otobio.brand : Otobio.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(destination == dest ? Otobio.cardBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}
