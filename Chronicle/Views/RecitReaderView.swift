import SwiftUI

/// Données d'un récit à lire en plein écran.
struct RecitReaderData: Identifiable {
    let id = UUID()
    let title: String
    let date: Date?
    let text: String
}

/// Page de lecture plein écran — ouvrir un récit comme on ouvre un chapitre.
struct RecitReaderView: View {
    let data: RecitReaderData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Otobio.recitCardBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(data.title)
                        .font(Otobio.serifTitle(28))
                        .foregroundStyle(Otobio.brand)
                        .padding(.top, 72)

                    if let date = data.date {
                        Text("Écrit le \(date.formatted(.dateTime.day().month(.wide).year()))")
                            .font(Otobio.micro())
                            .foregroundStyle(Otobio.textTertiary)
                            .padding(.top, 8)
                    }

                    Rectangle()
                        .fill(Otobio.separator)
                        .frame(width: 60, height: 0.5)
                        .padding(.vertical, 24)

                    Text(data.text)
                        .font(.custom("TimesNewRomanPSMT", size: 17))
                        .foregroundStyle(Otobio.textPrimary)
                        .lineSpacing(8)
                        .padding(.bottom, 60)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Otobio.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(Otobio.cardBackground)
                    .clipShape(Circle())
            }
            .padding(.trailing, 20)
            .padding(.top, 8)
        }
    }
}

#Preview {
    RecitReaderView(data: RecitReaderData(
        title: "Semaine du 12 au 18 janvier",
        date: Date(),
        text: String(repeating: "Cette semaine, j'ai retrouvé Marie au café pour discuter du projet. Nous avons beaucoup avancé et je suis rentré confiant. ", count: 8)
    ))
}
