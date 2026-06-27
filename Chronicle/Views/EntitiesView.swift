import SwiftUI
import CoreData

struct EntitiesView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Personne.frequenceMention, ascending: false)])
    private var personnes: FetchedResults<Personne>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Lieu.frequence, ascending: false)])
    private var lieux: FetchedResults<Lieu>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Evenement.dateEvenement, ascending: false)])
    private var evenements: FetchedResults<Evenement>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \Theme.occurrences, ascending: false)])
    private var themes: FetchedResults<Theme>

    @State private var showingAddSheet = false
    @State private var addType: EntityAddType = .person

    enum EntityAddType {
        case person, place
    }

    var body: some View {
        NavigationStack {
            List {
                // Personnes
                Section {
                    if personnes.isEmpty {
                        Text("Aucune personne détectée")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(personnes) { personne in
                        PersonneRow(personne: personne)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(personne) } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack {
                        Label("Personnes", systemImage: "person.2")
                        Spacer()
                        Button { addType = .person; showingAddSheet = true } label: {
                            Image(systemName: "plus.circle")
                        }
                    }
                }

                // Lieux
                Section {
                    if lieux.isEmpty {
                        Text("Aucun lieu détecté")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(lieux) { lieu in
                        LieuRow(lieu: lieu)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(lieu) } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack {
                        Label("Lieux", systemImage: "mappin.and.ellipse")
                        Spacer()
                        Button { addType = .place; showingAddSheet = true } label: {
                            Image(systemName: "plus.circle")
                        }
                    }
                }

                // Événements & Activités
                if !evenements.isEmpty {
                    Section {
                        ForEach(evenements) { event in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.titre ?? "")
                                        .font(.body)
                                    if let emotion = event.emotion {
                                        Text(emotion)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if let date = event.dateEvenement {
                                    Text(date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    viewContext.delete(event)
                                    try? viewContext.save()
                                } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Label("Événements & Activités", systemImage: "star")
                    }
                }

                // Thèmes
                if !themes.isEmpty {
                    Section {
                        ForEach(themes) { theme in
                            HStack {
                                Text(theme.label ?? "")
                                Spacer()
                                Text("\(theme.occurrences)x")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { delete(theme) } label: {
                                    Label("Supprimer", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Label("Thèmes", systemImage: "tag")
                    }
                }
            }
            .navigationTitle("Entités")
            .sheet(isPresented: $showingAddSheet) {
                AddEntitySheet(type: addType, isPresented: $showingAddSheet)
                    .environment(\.managedObjectContext, viewContext)
                    .presentationDetents([.medium])
            }
        }
    }

    private func delete(_ personne: Personne) {
        viewContext.delete(personne)
        try? viewContext.save()
    }

    private func delete(_ lieu: Lieu) {
        viewContext.delete(lieu)
        try? viewContext.save()
    }

    private func delete(_ theme: Theme) {
        viewContext.delete(theme)
        try? viewContext.save()
    }
}

struct PersonneRow: View {
    @ObservedObject var personne: Personne
    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var editedRelation: String = ""
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(personne.nom ?? "")
                    .font(.body)
                if let relation = personne.relation, !relation.isEmpty {
                    Text(relation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(personne.frequenceMention)x")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { isEditing = true }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                Form {
                    TextField("Nom", text: $editedName)
                    TextField("Relation", text: $editedRelation)
                }
                .navigationTitle("Modifier")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { isEditing = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") {
                            personne.nom = editedName
                            personne.relation = editedRelation.isEmpty ? nil : editedRelation
                            try? viewContext.save()
                            isEditing = false
                        }.bold()
                    }
                }
            }
            .presentationDetents([.medium])
            .onAppear {
                editedName = personne.nom ?? ""
                editedRelation = personne.relation ?? ""
            }
        }
    }
}

struct LieuRow: View {
    @ObservedObject var lieu: Lieu
    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var editedContext: String = ""
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(lieu.nom ?? "")
                    .font(.body)
                if let ctx = lieu.contexte, !ctx.isEmpty {
                    Text(ctx)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(lieu.frequence)x")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { isEditing = true }
        .sheet(isPresented: $isEditing) {
            NavigationStack {
                Form {
                    TextField("Nom", text: $editedName)
                    TextField("Contexte", text: $editedContext)
                }
                .navigationTitle("Modifier")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { isEditing = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") {
                            lieu.nom = editedName
                            lieu.contexte = editedContext.isEmpty ? nil : editedContext
                            try? viewContext.save()
                            isEditing = false
                        }.bold()
                    }
                }
            }
            .presentationDetents([.medium])
            .onAppear {
                editedName = lieu.nom ?? ""
                editedContext = lieu.contexte ?? ""
            }
        }
    }
}

struct AddEntitySheet: View {
    let type: EntitiesView.EntityAddType
    @Binding var isPresented: Bool
    @Environment(\.managedObjectContext) private var viewContext

    @State private var name = ""
    @State private var detail = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField(type == .person ? "Nom" : "Nom du lieu", text: $name)
                TextField(type == .person ? "Relation" : "Contexte", text: $detail)
            }
            .navigationTitle(type == .person ? "Nouvelle personne" : "Nouveau lieu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        addEntity()
                        isPresented = false
                    }
                    .bold()
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func addEntity() {
        switch type {
        case .person:
            let p = Personne(context: viewContext)
            p.id = UUID()
            p.nom = name
            p.relation = detail.isEmpty ? nil : detail
            p.frequenceMention = 0
        case .place:
            let l = Lieu(context: viewContext)
            l.id = UUID()
            l.nom = name
            l.contexte = detail.isEmpty ? nil : detail
            l.frequence = 0
        }
        try? viewContext.save()
    }
}
