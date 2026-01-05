import SwiftUI
import CoreData

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Paper.createdAt, ascending: false)],
        animation: .default
    )
    private var papers: FetchedResults<Paper>

    @State private var isShowingAddPaper = false
    @State private var paperBeingEdited: Paper? = nil

    // Sidebar selection (use objectID because it's Hashable)
    @State private var selectedPaperObjectID: NSManagedObjectID? = nil

    // Xcode-like pane visibility
    @State private var isSidebarVisible: Bool = true
    @State private var isInspectorVisible: Bool = true

    var body: some View {
        HSplitView {
            // LEFT: Sidebar
            if isSidebarVisible {
                sidebar
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
            }

            // CENTER: PDF / main content
            center
                .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)

            // RIGHT: Inspector
            if isInspectorVisible {
                InspectorView(paper: selectedPaper)
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 520)
            }
        }
        .toolbar {
            // Sidebar toggle (like Xcode)
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation { isSidebarVisible.toggle() }
                } label: {
                    Image(systemName: "sidebar.leading")
                }
                .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            }

            // Right-side actions
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    withAnimation { isInspectorVisible.toggle() }
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help(isInspectorVisible ? "Hide Inspector" : "Show Inspector")

                Button {
                    isShowingAddPaper = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Paper")
            }
        }
        .sheet(isPresented: $isShowingAddPaper) {
            AddPaperView()
                .environment(\.managedObjectContext, viewContext)
                .frame(minWidth: 700, minHeight: 650)
        }
        .sheet(item: $paperBeingEdited) { paper in
            AddPaperView(paperToEdit: paper)
                .environment(\.managedObjectContext, viewContext)
                .frame(minWidth: 700, minHeight: 650)
        }
    }

    private var sidebar: some View {
        List(selection: $selectedPaperObjectID) {
            ForEach(papers) { paper in
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayTitle(for: paper))
                        .font(.headline)

                    let authorsLine = authorsDisplay(from: paper.authorsJSON)
                    if !authorsLine.isEmpty {
                        Text(authorsLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(paper.objectID)
                .contextMenu {
                    Button("Edit") { paperBeingEdited = paper }
                    Divider()
                    Button("Delete", role: .destructive) { deletePaper(paper) }
                }
            }
            .onDelete(perform: deletePapers)
        }
        .listStyle(.sidebar)
    }

    private var center: some View {
        Group {
            if let paper = selectedPaper {
                PaperDetailView(paper: paper)
            } else {
                Text("Select a paper")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var selectedPaper: Paper? {
        guard let selectedPaperObjectID else { return nil }
        return papers.first(where: { $0.objectID == selectedPaperObjectID })
    }

    private func displayTitle(for paper: Paper) -> String {
        let short = (paper.shortTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !short.isEmpty { return short }
        return (paper.title ?? "Untitled")
    }

    private func authorsDisplay(from authorsJSON: String?) -> String {
        guard let authorsJSON, let data = authorsJSON.data(using: .utf8) else { return "" }
        do {
            let authors = try JSONDecoder().decode([AuthorInput].self, from: data)
            return authors
                .filter {
                    !$0.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    !$0.lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                .map { a in
                    let first = a.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let last = a.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if first.isEmpty { return last }
                    if last.isEmpty { return first }
                    return "\(last), \(first)"
                }
                .joined(separator: " • ")
        } catch {
            return ""
        }
    }

    private func deletePapers(offsets: IndexSet) {
        withAnimation {
            offsets.map { papers[$0] }.forEach(viewContext.delete)
            do { try viewContext.save() }
            catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func deletePaper(_ paper: Paper) {
        withAnimation {
            if selectedPaperObjectID == paper.objectID {
                selectedPaperObjectID = nil
            }
            viewContext.delete(paper)
            do { try viewContext.save() }
            catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

private struct PaperDetailView: View {
    let paper: Paper

    var body: some View {
        let pdfURL = normalizeArxivPDFURL(paper.arxivPDFURL ?? "")

        if pdfURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("No PDF available for this paper.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PDFRemoteViewer(urlString: pdfURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Shared with AddPaperView for decoding in the list UI.
struct AuthorInput: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var firstName: String
    var lastName: String
}
