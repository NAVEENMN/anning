import SwiftUI
import CoreData

private enum LeftNavigatorTab: Hashable {
    case papers
    case events
    case todos
}

private enum AppMode: Hashable {
    case microscope
    case person
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Papers
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Paper.createdAt, ascending: false)],
        animation: .default
    )
    private var papers: FetchedResults<Paper>

    // Events (base fetch ascending; we'll sort in-memory for the toggle)
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Event.date, ascending: true)],
        animation: .default
    )
    private var events: FetchedResults<Event>

    // Todos
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \TodoItem.date, ascending: false),
            NSSortDescriptor(keyPath: \TodoItem.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var todos: FetchedResults<TodoItem>

    @State private var navigatorTab: LeftNavigatorTab = .papers
    @State private var appMode: AppMode = .microscope

    // Sheets
    @State private var isShowingAddPaper = false
    @State private var isShowingAddEvent = false
    @State private var paperBeingEdited: Paper? = nil
    @State private var eventBeingEdited: Event? = nil

    // Selection
    @State private var selectedPaperObjectID: NSManagedObjectID? = nil
    @State private var selectedEventObjectID: NSManagedObjectID? = nil
    @State private var selectedTodoObjectID: NSManagedObjectID? = nil

    // UI
    @State private var isSidebarVisible: Bool = true
    @SceneStorage("isInspectorVisible") private var isInspectorVisible: Bool = false
    @State private var eventsSortAscending: Bool = true
    @SceneStorage("papersNotesFraction_v2") private var papersNotesFraction: Double = 0.50

    var body: some View {
        HSplitView {
            if isSidebarVisible {
                sidebar
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
            }

            center
                .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)

            if isInspectorVisible {
                inspector
                    .frame(minWidth: 320, idealWidth: 360, maxWidth: 520)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { withAnimation { isSidebarVisible.toggle() } } label: {
                    Image(systemName: "sidebar.leading")
                }
                .help(isSidebarVisible ? "Hide Sidebar" : "Show Sidebar")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button { withAnimation { isInspectorVisible.toggle() } } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help(isInspectorVisible ? "Hide Inspector" : "Show Inspector")

                Button {
                    guard appMode == .microscope else { return }

                    switch navigatorTab {
                    case .papers:
                        isShowingAddPaper = true
                    case .events:
                        isShowingAddEvent = true
                    case .todos:
                        addTodoItem()
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help(appMode == .person ? "Unavailable in Person view" :
                      (navigatorTab == .papers ? "Add Paper" : (navigatorTab == .events ? "Add Event" : "Add Todo")))
                .disabled(appMode == .person)
            }
        }
        .sheet(isPresented: $isShowingAddPaper) {
            AddPaperView()
                .environment(\.managedObjectContext, viewContext)
                .frame(minWidth: 700, minHeight: 650)
        }
        .sheet(isPresented: $isShowingAddEvent) {
            AddEventView()
                .environment(\.managedObjectContext, viewContext)
                .frame(minWidth: 560, minHeight: 520)
        }
        .sheet(item: $paperBeingEdited) { paper in
            AddPaperView(paperToEdit: paper)
                .environment(\.managedObjectContext, viewContext)
                .frame(minWidth: 700, minHeight: 650)
        }
        .sheet(item: $eventBeingEdited) { e in
            AddEventView(eventToEdit: e)
                .environment(\.managedObjectContext, viewContext)
                .frame(minWidth: 560, minHeight: 520)
        }
        .onReceive(NotificationCenter.default.publisher(for: .anningSplitFractionChanged)) { note in
            if let v = note.object as? Double {
                papersNotesFraction = v
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {

            // Top navigator strip (only in Microscope mode)
            if appMode == .microscope {
                HStack(spacing: 8) {
                    navButton(tab: .papers, systemImage: "folder", selectedSystemImage: "folder.fill", help: "Papers")
                    navButton(tab: .events, systemImage: "list.bullet", selectedSystemImage: "list.bullet", help: "Events")
                    navButton(tab: .todos, systemImage: "checkmark.circle", selectedSystemImage: "checkmark.circle.fill", help: "Todo")
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                Divider()

                Group {
                    if navigatorTab == .papers {
                        papersList
                    } else if navigatorTab == .events {
                        eventsList
                    } else {
                        todosList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
            } else {
                // Person mode: keep the list area empty
                Spacer()
            }

            if appMode == .microscope {
                ResearchObjectivePanel()
                    .frame(maxWidth: .infinity)

                Divider()
            }

            // Bottom-most: mode switcher (always visible)
            modeSwitcher
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
        }
    }

    private var modeSwitcher: some View {
        HStack(spacing: 10) {
            modeButton(.microscope, systemImage: "doc.on.doc", help: "Papers")
            modeButton(.person, systemImage: "person", help: "Person")
            Spacer()
        }
    }

    private func modeButton(_ mode: AppMode, systemImage: String, help: String) -> some View {
        let selected = (appMode == mode)

        return Button {
            withAnimation {
                appMode = mode

                // When leaving microscope mode, clear selections to avoid weird state
                if mode == .person {
                    selectedPaperObjectID = nil
                    selectedEventObjectID = nil
                    selectedTodoObjectID = nil
                }
            }
        } label: {
            Image(systemName: systemImage)
                .foregroundStyle(selected ? .white : .secondary)
                .frame(width: 30, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func navButton(tab: LeftNavigatorTab,
                           systemImage: String,
                           selectedSystemImage: String,
                           help: String) -> some View {
        let selected = (navigatorTab == tab)
        return Button {
            switchNavigator(to: tab)
        } label: {
            Image(systemName: selected ? selectedSystemImage : systemImage)
                .foregroundStyle(selected ? .white : .secondary)
                .frame(width: 30, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func switchNavigator(to tab: LeftNavigatorTab) {
        guard appMode == .microscope else { return }
        guard tab != navigatorTab else { return }
        navigatorTab = tab
        // Clear selection when switching modes (keeps center/inspector consistent)
        selectedPaperObjectID = nil
        selectedEventObjectID = nil
        selectedTodoObjectID = nil
    }

    private var papersList: some View {
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
        }
        .listStyle(.sidebar)
    }

    private var eventsList: some View {
        List(selection: $selectedEventObjectID) {
            ForEach(eventsSorted) { e in
                VStack(alignment: .leading, spacing: 6) {
                    Text(e.shortTitle)
                        .font(.headline)

                    Text(dateOnlyFormatter.string(from: e.date))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .tag(e.objectID)
                .contextMenu {
                    Button("Edit") {
                        eventBeingEdited = viewContext.object(with: e.objectID) as? Event
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        deleteEventByID(e.objectID)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var todosList: some View {
        List(selection: $selectedTodoObjectID) {
            ForEach(todos) { t in
                VStack(alignment: .leading, spacing: 6) {
                    Text(t.todoText?.isEmpty == false ? (t.todoText ?? "") : "Enter todo")
                        .font(.headline)

                    HStack(spacing: 8) {
                        Text(dateOnlyFormatter.string(from: t.date ?? Date()))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(todoPriorityFromStored(t.priority).label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(t.objectID)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Center

    private var center: some View {
        Group {
            if appMode == .person {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Microscope mode
                if navigatorTab == .papers {
                    if let paper = selectedPaper {
                        PersistentVSplitView(bottomFraction: $papersNotesFraction, minTop: 320, minBottom: 240) {
                            PaperDetailView(paper: paper)
                        } bottom: {
                            NotesPanel(paper: paper)
                        }
                    } else {
                        Text("Select a paper")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if navigatorTab == .events {
                    EventsCenterView(
                        rows: eventsSorted,
                        selection: eventSelectionSetBinding,
                        sortAscending: $eventsSortAscending
                    )
                } else {
                    TodoCenterView(rows: todos.map { TodoRow(item: $0) }, selection: todoSelectionSetBinding)
                }
            }
        }
    }

    // MARK: - Inspector

    private var inspector: some View {
        Group {
            if appMode == .person {
                Color.clear
            } else {
                if navigatorTab == .papers {
                    InspectorView(paper: selectedPaper)
                        .id(selectedPaper?.objectID)
                } else if navigatorTab == .events {
                    EventInspectorView(event: selectedEvent)
                        .id(selectedEvent?.objectID)
                } else {
                    Color.clear
                }
            }
        }
    }

    // MARK: - Data + selection helpers

    private var selectedPaper: Paper? {
        guard let id = selectedPaperObjectID else { return nil }
        return viewContext.object(with: id) as? Paper
    }

    private var selectedEvent: Event? {
        guard let id = selectedEventObjectID else { return nil }
        return viewContext.object(with: id) as? Event
    }

    private var eventsSorted: [EventRow] {
        let base = events.compactMap { ev -> EventRow? in
            guard let date = ev.date else { return nil }
            return EventRow(
                objectID: ev.objectID,
                date: date,
                shortTitle: ev.shortTitle ?? "",
                eventType: eventTypeFromStored(ev.eventType),
                url: ev.url
            )
        }

        return base.sorted {
            eventsSortAscending ? ($0.date < $1.date) : ($0.date > $1.date)
        }
    }

    private var eventSelectionSetBinding: Binding<Set<NSManagedObjectID>> {
        Binding(
            get: { selectedEventObjectID.map { [$0] } ?? [] },
            set: { newSet in selectedEventObjectID = newSet.first }
        )
    }

    private var todoSelectionSetBinding: Binding<Set<NSManagedObjectID>> {
        Binding(
            get: { selectedTodoObjectID.map { [$0] } ?? [] },
            set: { newSet in selectedTodoObjectID = newSet.first }
        )
    }

    // MARK: - Helpers

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

    private func deletePaper(_ paper: Paper) {
        withAnimation {
            if selectedPaperObjectID == paper.objectID { selectedPaperObjectID = nil }
            viewContext.delete(paper)
            do { try viewContext.save() }
            catch { let nsError = error as NSError; fatalError("Unresolved error \(nsError), \(nsError.userInfo)") }
        }
    }

    private func deleteEventByID(_ id: NSManagedObjectID) {
        withAnimation {
            if selectedEventObjectID == id {
                selectedEventObjectID = nil
            }
            if let obj = try? viewContext.existingObject(with: id) {
                viewContext.delete(obj)
                try? viewContext.save()
            }
        }
    }

    private func addTodoItem() {
        withAnimation {
            let t = TodoItem(context: viewContext)
            t.id = UUID()
            t.date = Date()
            t.priority = "p3"
            t.todoText = ""
            t.isDone = false
            t.createdAt = Date()

            do {
                try viewContext.save()
                selectedTodoObjectID = t.objectID
            } catch {
                print("Failed to add todo:", error)
            }
        }
    }
}

private struct PaperDetailView: View {
    let paper: Paper
    var body: some View { PaperPDFViewer(paper: paper) }
}

struct EventRow: Identifiable {
    let objectID: NSManagedObjectID
    let date: Date
    let shortTitle: String
    let eventType: EventType
    let url: String?
    var id: NSManagedObjectID { objectID }
}

struct EventsCenterView: View {
    let rows: [EventRow]
    @Binding var selection: Set<NSManagedObjectID>
    @Binding var sortAscending: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Events").font(.headline).foregroundStyle(.secondary)
                Spacer()
                Button { sortAscending.toggle() } label: {
                    Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                }
                .buttonStyle(.borderless)
            }
            .padding(10)

            Divider()

            Table(rows, selection: $selection) {
                TableColumn("Date") { r in Text(dateOnlyFormatter.string(from: r.date)) }
                TableColumn("Type") { r in
                    Label(r.eventType.displayName, systemImage: r.eventType.systemImage)
                        .labelStyle(.titleAndIcon)
                }
                TableColumn("Short title") { r in Text(r.shortTitle) }
                TableColumn("URL") { r in
                    if let s = r.url, !s.isEmpty, let link = URL(string: s) {
                        Link("Link", destination: link)
                    } else { Text("") }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private let dateOnlyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
}()
