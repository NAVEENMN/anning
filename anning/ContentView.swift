import SwiftUI
import CoreData

private enum LeftNavigatorTab: Hashable {
    case papers
    case events
    case todos
    case definitions
}

private enum AppMode: Hashable {
    case microscope
    case person
    case settings
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext

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

    // Definitions
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DefinitionItem.createdAt, ascending: false)],
        animation: .default
    )
    private var definitions: FetchedResults<DefinitionItem>

    @State private var navigatorTab: LeftNavigatorTab = .papers
    @State private var appMode: AppMode = .microscope
    @State private var lastNonSettingsMode: AppMode = .microscope

    // Sheets
    @State private var isShowingAddPaper = false
    @State private var isShowingAddEvent = false
    @State private var paperBeingEdited: Paper? = nil
    @State private var eventBeingEdited: Event? = nil

    // Selection
    @State private var selectedPaperObjectID: NSManagedObjectID? = nil
    @State private var selectedEventObjectID: NSManagedObjectID? = nil
    @State private var selectedTodoObjectID: NSManagedObjectID? = nil
    @State private var selectedDefinitionObjectID: NSManagedObjectID? = nil
    @State private var settingsSelection: SettingsSection = .account

    // UI
    @State private var isSidebarVisible: Bool = true
    @SceneStorage("isInspectorVisible") private var isInspectorVisible: Bool = false
    @State private var eventsSortAscending: Bool = true
    @SceneStorage("papersNotesFraction_v2") private var papersNotesFraction: Double = 0.50

    // Toast
    @State private var toastMessage: String? = nil
    @State private var toastVisible: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            HSplitView {
                if isSidebarVisible {
                    sidebar
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
                }

                center
                    .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)

                if isInspectorVisible && appMode == .microscope {
                    inspector
                        .frame(minWidth: 320, idealWidth: 360, maxWidth: 520)
                }
            }

            if toastVisible, let msg = toastMessage {
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 8)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
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
                if appMode == .settings {
                    Button {
                        withAnimation {
                            appMode = lastNonSettingsMode
                        }
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .help("Back")
                } else {
                    // Inspector toggle only makes sense in microscope
                    if appMode == .microscope {
                        Button { withAnimation { isInspectorVisible.toggle() } } label: {
                            Image(systemName: "sidebar.trailing")
                        }
                        .help(isInspectorVisible ? "Hide Inspector" : "Show Inspector")
                    }

                    // Plus disabled outside microscope, and not shown on settings
                    Button {
                        guard appMode == .microscope else { return }
                        switch navigatorTab {
                        case .papers:
                            isShowingAddPaper = true
                        case .events:
                            isShowingAddEvent = true
                        case .todos:
                            addTodoItem()
                        case .definitions:
                            addDefinitionItem()
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help(appMode == .person ? "Unavailable in Person view" :
                          (navigatorTab == .papers ? "Add Paper" : (navigatorTab == .events ? "Add Event" : (navigatorTab == .todos ? "Add Todo" : "Add Definition"))))
                    .disabled(appMode != .microscope)
                }
            }
        }
        .sheet(isPresented: $isShowingAddPaper) {
            AddPaperView()
                .environment(\.managedObjectContext, viewContext)
                .frame(minWidth: 560, minHeight: 320)
        }
        .sheet(isPresented: $isShowingAddEvent) {
            AddEventView()
                .environment(\.managedObjectContext, viewContext)
                .frame(minWidth: 560, minHeight: 520)
        }
        .sheet(item: $paperBeingEdited) { paper in
            AddPaperView(paperToEdit: paper)
                .environment(\.managedObjectContext, viewContext)
                .frame(minWidth: 560, minHeight: 320)
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
                    navButton(tab: .definitions, systemImage: "brain", selectedSystemImage: "brain.fill", help: "Definitions")
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
                    } else if navigatorTab == .definitions {
                        definitionsList
                    } else {
                        todosList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
            } else if appMode == .settings {
                // Settings mode: show settings navigation inside the app sidebar
                List(selection: $settingsSelection) {
                    Label("Account", systemImage: "at")
                        .tag(SettingsSection.account)

                    Label("General", systemImage: "gearshape")
                        .tag(SettingsSection.general)
                }
                .listStyle(.sidebar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Person mode: empty list area
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

            // Social (coming soon)
            Button {
                showToast("Social features coming soon")
            } label: {
                Image(systemName: "person")
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 24)
            }
            .buttonStyle(.plain)
            .help("Social")

            Spacer()

            settingsButton
        }
    }

    private var settingsButton: some View {
        let selected = (appMode == .settings)

        return Button {
            withAnimation {
                if appMode != .settings {
                    lastNonSettingsMode = appMode
                }
                appMode = .settings
            }
        } label: {
            Image(systemName: selected ? "gearshape.fill" : "gearshape")
                .foregroundStyle(selected ? .white : .secondary)
                .frame(width: 30, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(selected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help("Settings")
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
                    selectedDefinitionObjectID = nil
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
        selectedDefinitionObjectID = nil
    }

    private var papersList: some View {
        PaperSidebarTreeView(
            selection: $selectedPaperObjectID,
            paperBeingEdited: $paperBeingEdited
        )
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

    private var definitionsList: some View {
        List(selection: $selectedDefinitionObjectID) {
            ForEach(definitions) { d in
                VStack(alignment: .leading, spacing: 6) {
                    Text((d.term ?? "").isEmpty ? "new term" : (d.term ?? "new term"))
                        .font(.headline)
                }
                .tag(d.objectID)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Center

    private var center: some View {
        Group {
            if appMode == .settings {
                SettingsView(selection: $settingsSelection)
            } else if appMode == .person {
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
                } else if navigatorTab == .definitions {
                    DefinitionsCenterView(
                        rows: definitions.map { DefinitionRow(item: $0) },
                        selection: definitionSelectionSetBinding
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

    private var definitionSelectionSetBinding: Binding<Set<NSManagedObjectID>> {
        Binding(
            get: { selectedDefinitionObjectID.map { [$0] } ?? [] },
            set: { newSet in selectedDefinitionObjectID = newSet.first }
        )
    }

    // MARK: - Helpers

    private func showToast(_ message: String) {
        toastMessage = message
        withAnimation(.easeOut(duration: 0.15)) {
            toastVisible = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeIn(duration: 0.2)) {
                toastVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                toastMessage = nil
            }
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

    private func addDefinitionItem() {
        withAnimation {
            let d = DefinitionItem(context: viewContext)
            d.id = UUID()
            d.createdAt = Date()
            d.term = "new term"
            d.definitionText = ""

            do {
                try viewContext.save()
                selectedDefinitionObjectID = d.objectID
            } catch {
                print("Failed to add definition:", error)
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
