import Foundation
import CoreData

// MARK: - Codable project file

struct ProjectFile: Codable {
    var version: Int = 1
    var exportedAt: Date
    var workspaces: [WorkspaceDTO]
    var papers: [PaperDTO]
    var events: [EventDTO]
    var todos: [TodoDTO]
}

struct WorkspaceDTO: Codable {
    var id: UUID?
    var createdAt: Date?
    var projectTitle: String?
    var researchObjective: String?
}

struct PaperDTO: Codable {
    var id: UUID?
    var title: String?
    var shortTitle: String?
    var abstractText: String?
    var arxivPDFURL: String?
    var authorsJSON: String?
    var notesJSON: String?
    var paperType: String?
    var createdAt: Date?
    // We do NOT persist localPDFPath (machine-specific cache)
}

struct EventDTO: Codable {
    var id: UUID?
    var date: Date?
    var shortTitle: String?
    var summaryText: String?
    var eventType: String?
    var url: String?
    var createdAt: Date?
}

struct TodoDTO: Codable {
    var id: UUID?
    var date: Date?
    var priority: String?
    var todoText: String?
    var isDone: Bool?
    var createdAt: Date?
}

// MARK: - Export / Import

enum ProjectIO {
    static func exportJSON(context: NSManagedObjectContext) throws -> Data {
        let fetchWorkspaces = NSFetchRequest<Workspace>(entityName: "Workspace")
        fetchWorkspaces.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        let fetchPapers = NSFetchRequest<Paper>(entityName: "Paper")
        fetchPapers.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        let fetchEvents = NSFetchRequest<Event>(entityName: "Event")
        fetchEvents.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

        let fetchTodos = NSFetchRequest<TodoItem>(entityName: "TodoItem")
        fetchTodos.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        let ws = try context.fetch(fetchWorkspaces).map {
            WorkspaceDTO(
                id: $0.id,
                createdAt: $0.createdAt,
                projectTitle: $0.projectTitle,
                researchObjective: $0.researchObjective
            )
        }

        let papers = try context.fetch(fetchPapers).map {
            PaperDTO(
                id: $0.id,
                title: $0.title,
                shortTitle: $0.shortTitle,
                abstractText: $0.abstractText,
                arxivPDFURL: $0.arxivPDFURL,
                authorsJSON: $0.authorsJSON,
                notesJSON: $0.notesJSON,
                paperType: $0.paperType,
                createdAt: $0.createdAt
            )
        }

        let events = try context.fetch(fetchEvents).map {
            EventDTO(
                id: $0.id,
                date: $0.date,
                shortTitle: $0.shortTitle,
                summaryText: $0.summaryText,
                eventType: $0.eventType,
                url: $0.url,
                createdAt: $0.createdAt
            )
        }

        let todos = try context.fetch(fetchTodos).map {
            TodoDTO(
                id: $0.id,
                date: $0.date,
                priority: $0.priority,
                todoText: $0.todoText,
                isDone: $0.isDone,
                createdAt: $0.createdAt
            )
        }

        let file = ProjectFile(
            exportedAt: Date(),
            workspaces: ws,
            papers: papers,
            events: events,
            todos: todos
        )

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(file)
    }

    static func importJSON(data: Data, context: NSManagedObjectContext) throws {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let file = try dec.decode(ProjectFile.self, from: data)

        try wipeAll(context: context)

        // Workspaces (must exist for your UI)
        for w in file.workspaces {
            let obj = Workspace(context: context)
            obj.id = w.id ?? UUID()
            obj.createdAt = w.createdAt ?? Date()
            obj.projectTitle = w.projectTitle ?? ""
            obj.researchObjective = w.researchObjective ?? ""
        }
        // If project had none, create one
        if file.workspaces.isEmpty {
            let obj = Workspace(context: context)
            obj.id = UUID()
            obj.createdAt = Date()
            obj.projectTitle = ""
            obj.researchObjective = ""
        }

        for p in file.papers {
            let obj = Paper(context: context)
            obj.id = p.id ?? UUID()
            obj.title = p.title ?? ""
            obj.shortTitle = p.shortTitle ?? ""
            obj.abstractText = p.abstractText ?? ""
            obj.arxivPDFURL = p.arxivPDFURL ?? ""
            obj.authorsJSON = p.authorsJSON ?? "[]"
            obj.notesJSON = p.notesJSON ?? "{}"
            obj.paperType = p.paperType ?? "empirical work"
            obj.createdAt = p.createdAt ?? Date()
            obj.localPDFPath = nil // force re-download cache on this machine
        }

        for e in file.events {
            let obj = Event(context: context)
            obj.id = e.id ?? UUID()
            obj.date = e.date ?? Date()
            obj.shortTitle = e.shortTitle ?? ""
            obj.summaryText = e.summaryText ?? ""
            obj.eventType = e.eventType ?? "informative"
            obj.url = e.url
            obj.createdAt = e.createdAt ?? Date()
        }

        for t in file.todos {
            let obj = TodoItem(context: context)
            obj.id = t.id ?? UUID()
            obj.date = t.date ?? Date()
            obj.priority = t.priority ?? "p3"
            obj.todoText = t.todoText ?? ""
            obj.isDone = t.isDone ?? false
            obj.createdAt = t.createdAt ?? Date()
        }

        try context.save()
    }

    static func resetDatabase(context: NSManagedObjectContext) throws {
        try wipeAll(context: context)
        try context.save()
    }

    static func wipeAll(context: NSManagedObjectContext) throws {
        try batchDelete(entityName: "Paper", context: context)
        try batchDelete(entityName: "Event", context: context)
        try batchDelete(entityName: "TodoItem", context: context)
        try batchDelete(entityName: "Workspace", context: context)
    }

    private static func batchDelete(entityName: String, context: NSManagedObjectContext) throws {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        let req = NSBatchDeleteRequest(fetchRequest: fetch)
        req.resultType = .resultTypeObjectIDs
        let result = try context.execute(req) as? NSBatchDeleteResult
        if let deleted = result?.result as? [NSManagedObjectID], !deleted.isEmpty {
            let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: deleted]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        }
    }
}

