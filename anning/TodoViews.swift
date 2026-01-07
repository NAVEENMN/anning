import SwiftUI
import CoreData

enum TodoPriority: String, CaseIterable, Identifiable {
    case p1, p2, p3
    var id: String { rawValue }
    var label: String { rawValue.uppercased() } // "P1"
}

func todoPriorityFromStored(_ s: String?) -> TodoPriority {
    TodoPriority(rawValue: (s ?? "").lowercased()) ?? .p3
}

struct TodoRow: Identifiable {
    let item: TodoItem
    var id: NSManagedObjectID { item.objectID }
}

struct TodoCenterView: View {
    @Environment(\.managedObjectContext) private var viewContext

    let rows: [TodoRow]
    @Binding var selection: Set<NSManagedObjectID>

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Todo")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)

            Divider()

            Table(rows, selection: $selection) {
                TableColumn("Date") { r in
                    Text(dateOnlyFormatter.string(from: r.item.date ?? Date()))
                }

                TableColumn("Priority") { r in
                    TodoPriorityCell(item: r.item)
                }

                TableColumn("Todo") { r in
                    TodoTextCell(item: r.item)
                }

                TableColumn("") { r in
                    TodoActionsCell(item: r.item)
                }
                .width(70)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct TodoPriorityCell: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var item: TodoItem

    @State private var priority: TodoPriority = .p3

    var body: some View {
        Picker("", selection: $priority) {
            ForEach(TodoPriority.allCases) { p in
                Text(p.label).tag(p)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .onAppear {
            priority = todoPriorityFromStored(item.priority)
        }
        .onChange(of: item.objectID) {
            priority = todoPriorityFromStored(item.priority)
        }
        .onChange(of: priority) {
            item.priority = priority.rawValue
            try? viewContext.save()
        }
    }
}

private struct TodoTextCell: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var item: TodoItem

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            TextField("Enter todo", text: $draft)
                .textFieldStyle(.plain)
                .focused($focused)
                .onAppear { draft = item.todoText ?? "" }
                .onChange(of: item.objectID) { draft = item.todoText ?? "" }
                .onChange(of: focused) {
                    if !focused {
                        item.todoText = draft
                        try? viewContext.save()
                    }
                }

            if item.isDone {
                Rectangle()
                    .fill(Color.secondary.opacity(0.7))
                    .frame(height: 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct TodoActionsCell: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var item: TodoItem

    var body: some View {
        HStack(spacing: 10) {
            Button {
                item.isDone.toggle()
                try? viewContext.save()
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .buttonStyle(.borderless)
            .help(item.isDone ? "Mark as not done" : "Mark as done")

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
}

private let dateOnlyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
}()

