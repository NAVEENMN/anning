import SwiftUI
import CoreData

struct DefinitionRow: Identifiable {
    let item: DefinitionItem
    var id: NSManagedObjectID { item.objectID }
}

struct DefinitionsCenterView: View {
    let rows: [DefinitionRow]
    @Binding var selection: Set<NSManagedObjectID>

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Definitions")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)

            Divider()

            Table(rows, selection: $selection) {
                TableColumn("Term") { r in
                    DefinitionTermCell(item: r.item)
                }
                .width(min: 160, ideal: 220)

                TableColumn("Definition") { r in
                    DefinitionTextCell(item: r.item)
                }

                TableColumn("") { r in
                    DefinitionActionsCell(item: r.item)
                }
                .width(50)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct DefinitionTermCell: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var item: DefinitionItem

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .focused($focused)
            .onAppear { draft = item.term ?? "" }
            .onChange(of: item.objectID) { draft = item.term ?? "" }
            .onChange(of: focused) {
                if !focused {
                    item.term = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    try? viewContext.save()
                }
            }
    }
}

private struct DefinitionTextCell: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var item: DefinitionItem

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        // Multiline-capable TextField on modern macOS
        TextField("Enter definition", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...4)
            .focused($focused)
            .onAppear { draft = item.definitionText ?? "" }
            .onChange(of: item.objectID) { draft = item.definitionText ?? "" }
            .onChange(of: focused) {
                if !focused {
                    item.definitionText = draft
                    try? viewContext.save()
                }
            }
    }
}

private struct DefinitionActionsCell: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var item: DefinitionItem

    var body: some View {
        Button(role: .destructive) {
            viewContext.delete(item)
            try? viewContext.save()
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .help("Delete")
    }
}

