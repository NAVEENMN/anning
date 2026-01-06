import SwiftUI
import CoreData

struct ResearchObjectivePanel: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Workspace.createdAt, ascending: true)],
        animation: .default
    )
    private var workspaces: FetchedResults<Workspace>

    @State private var draft: String = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    private var workspace: Workspace? { workspaces.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Research Objective")
                .font(.callout)
                .fontWeight(.semibold)

            if isEditing {
                TextEditor(text: $draft)
                    .focused($isFocused)
                    .font(.callout)
                    .frame(minHeight: 110, maxHeight: 160)
                    .padding(6)
                    .background(Color.black.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.20))
                    )
                    .onChange(of: isFocused) {
                        if !isFocused {
                            save()
                            isEditing = false
                        }
                    }
            } else {
                Text(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "Click to add your research objective…"
                     : draft)
                    .font(.callout)
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.black.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.12))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditing = true
                        isFocused = true
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 170)
        .onAppear {
            ensureWorkspace()
            load()
        }
        .onChange(of: workspaces.count) {
            load()
        }
        .onDisappear {
            // safety: persist if user closes while editing
            if isEditing { save() }
        }
    }

    private func ensureWorkspace() {
        if workspace == nil {
            let w = Workspace(context: viewContext)
            w.id = UUID()
            w.createdAt = Date()
            w.researchObjective = ""
            do { try viewContext.save() }
            catch { print("Failed to create Workspace:", error) }
        }
    }

    private func load() {
        draft = workspace?.researchObjective ?? ""
    }

    private func save() {
        guard let w = workspace else { return }
        w.researchObjective = draft
        do { try viewContext.save() }
        catch { print("Failed to save research objective:", error) }
    }
}
