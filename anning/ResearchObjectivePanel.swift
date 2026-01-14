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

    private var workspace: Workspace? { workspaces.first }

    var body: some View {
        InlineMarkdownEditor(
            title: "Research Objective",
            text: $draft,
            placeholder: "Click to add your research objective…"
        ) {
            save()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 170, alignment: .topLeading)
        .onAppear {
            ensureWorkspace()
            load()
        }
        .onChange(of: workspaces.count) {
            load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .anningProjectDidLoad)) { _ in
            ensureWorkspace()
            load()
        }
    }

    private func ensureWorkspace() {
        if workspace == nil {
            let w = Workspace(context: viewContext)
            w.id = UUID()
            w.createdAt = Date()
            w.projectTitle = ""
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
