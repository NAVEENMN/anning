import SwiftUI
import CoreData
import UniformTypeIdentifiers

private let paperDragUTI = UTType.text.identifier

struct PaperSidebarTreeView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "orderIndex", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ],
        animation: .default
    )
    private var groups: FetchedResults<PaperGroup>

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(key: "sortIndex", ascending: true),
            NSSortDescriptor(key: "createdAt", ascending: true)
        ],
        animation: .default
    )
    private var papers: FetchedResults<Paper>

    // selected paper (drives the center PDF+Notes)
    @Binding var selection: NSManagedObjectID?
    @Binding var paperBeingEdited: Paper?

    @State private var expandedGroups: Set<NSManagedObjectID> = []
    @State private var renamingGroupID: NSManagedObjectID? = nil
    @State private var renameDraft: String = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                // Root groups
                ForEach(rootGroups) { g in
                    GroupCardNodeView(
                        group: g,
                        level: 0,
                        selection: $selection,
                        paperBeingEdited: $paperBeingEdited,
                        expandedGroups: $expandedGroups,
                        renamingGroupID: $renamingGroupID,
                        renameDraft: $renameDraft,
                        subgroups: subgroups,
                        papersInGroup: papersInGroup,
                        deleteGroup: deleteGroup,
                        createSubgroup: createSubgroup
                    )
                }

                // Ungrouped
                if !ungroupedPapers.isEmpty {
                    sectionHeader("Ungrouped")

                    ForEach(ungroupedPapers) { p in
                        PaperCardRow(
                            paper: p,
                            isSelected: selection == p.objectID
                        ) {
                            selection = p.objectID
                        } onEdit: {
                            paperBeingEdited = p
                        } onDelete: {
                            deletePaper(p)
                        }
                        .padding(.leading, 8)
                        .onDrag {
                            NSItemProvider(object: p.objectID.uriRepresentation().absoluteString as NSString)
                        }
                        .onDrop(of: [paperDragUTI],
                                delegate: PaperReorderDropDelegate(viewContext: viewContext,
                                                                   targetPaper: p,
                                                                   targetGroup: nil))
                    }
                }

                Spacer(minLength: 10)
            }
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .contextMenu {
            Button {
                createRootGroup(name: "New Group")
            } label: {
                Label("New Group", systemImage: "folder.badge.plus")
            }
        }
        .onAppear {
            // Expand any group that isn't collapsed
            expandedGroups = Set(groups.filter { !$0.isCollapsed }.map { $0.objectID })
        }
    }

    // MARK: - Data helpers

    private var rootGroups: [PaperGroup] {
        groups.filter { $0.parent == nil }
            .sorted { $0.orderIndex < $1.orderIndex }
    }

    private func subgroups(of group: PaperGroup) -> [PaperGroup] {
        let children = (group.children as? Set<PaperGroup>) ?? []
        return children.sorted { $0.orderIndex < $1.orderIndex }
    }

    private var ungroupedPapers: [Paper] {
        papers.filter { $0.group == nil }.sorted(by: paperSort)
    }

    private func papersInGroup(_ group: PaperGroup) -> [Paper] {
        papers.filter { $0.group == group }.sorted(by: paperSort)
    }

    private func paperSort(_ a: Paper, _ b: Paper) -> Bool {
        if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
        return (a.createdAt ?? .distantPast) < (b.createdAt ?? .distantPast)
    }

    // MARK: - Group CRUD

    private func createRootGroup(name: String) {
        let g = PaperGroup(context: viewContext)
        g.id = UUID()
        g.createdAt = Date()
        g.name = name
        g.parent = nil
        g.isCollapsed = false

        let next = (rootGroups.map { Int($0.orderIndex) }.max() ?? -1) + 1
        g.orderIndex = Int32(next)

        try? viewContext.save()

        expandedGroups.insert(g.objectID)
        renamingGroupID = g.objectID
        renameDraft = g.name ?? ""
    }

    private func createSubgroup(parent: PaperGroup) {
        let g = PaperGroup(context: viewContext)
        g.id = UUID()
        g.createdAt = Date()
        g.name = "New Subgroup"
        g.parent = parent
        g.isCollapsed = false

        let siblings = subgroups(of: parent)
        let next = (siblings.map { Int($0.orderIndex) }.max() ?? -1) + 1
        g.orderIndex = Int32(next)

        try? viewContext.save()

        expandedGroups.insert(parent.objectID)
        expandedGroups.insert(g.objectID)
        renamingGroupID = g.objectID
        renameDraft = g.name ?? ""
    }

    private func deleteGroup(_ group: PaperGroup) {
        let parent = group.parent

        // Move papers in this group to parent (or ungrouped)
        for p in papersInGroup(group) { p.group = parent }

        // Move papers in subgroups (2nd level) and delete subgroups
        for child in subgroups(of: group) {
            for p in papersInGroup(child) { p.group = parent }
            viewContext.delete(child)
        }

        // If currently selected paper is inside this group, keep selection (it was moved)
        // (no action needed)

        viewContext.delete(group)
        try? viewContext.save()
    }

    private func deletePaper(_ paper: Paper) {
        if selection == paper.objectID { selection = nil }
        viewContext.delete(paper)
        try? viewContext.save()
    }

    // MARK: - UI helpers

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

//
// MARK: - Group Node (card-based, recursive, 2-level)
//
// Each group row + its children are rendered as normal SwiftUI views.
// Papers are clickable cards that set selection manually.
//

private struct GroupCardNodeView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @ObservedObject var group: PaperGroup
    let level: Int

    @Binding var selection: NSManagedObjectID?
    @Binding var paperBeingEdited: Paper?
    @Binding var expandedGroups: Set<NSManagedObjectID>
    @Binding var renamingGroupID: NSManagedObjectID?
    @Binding var renameDraft: String

    let subgroups: (PaperGroup) -> [PaperGroup]
    let papersInGroup: (PaperGroup) -> [Paper]
    let deleteGroup: (PaperGroup) -> Void
    let createSubgroup: (PaperGroup) -> Void

    private var isExpanded: Bool { expandedGroups.contains(group.objectID) }
    private var isRenaming: Bool { renamingGroupID == group.objectID }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            groupHeader

            if isExpanded {
                // Subgroups (only for root groups => 2-level total)
                if level == 0 {
                    ForEach(subgroups(group)) { child in
                        GroupCardNodeView(
                            group: child,
                            level: 1,
                            selection: $selection,
                            paperBeingEdited: $paperBeingEdited,
                            expandedGroups: $expandedGroups,
                            renamingGroupID: $renamingGroupID,
                            renameDraft: $renameDraft,
                            subgroups: subgroups,
                            papersInGroup: papersInGroup,
                            deleteGroup: deleteGroup,
                            createSubgroup: createSubgroup
                        )
                        .padding(.leading, 14)
                    }
                }

                // Papers in this group
                ForEach(papersInGroup(group)) { p in
                    PaperCardRow(
                        paper: p,
                        isSelected: selection == p.objectID
                    ) {
                        selection = p.objectID
                    } onEdit: {
                        paperBeingEdited = p
                    } onDelete: {
                        viewContext.delete(p)
                        try? viewContext.save()
                        if selection == p.objectID { selection = nil }
                    }
                    .padding(.leading, level == 0 ? 14 : 28)
                    .onDrag {
                        NSItemProvider(object: p.objectID.uriRepresentation().absoluteString as NSString)
                    }
                    .onDrop(
                        of: [paperDragUTI],
                        delegate: PaperReorderDropDelegate(
                            viewContext: viewContext,
                            targetPaper: p,
                            targetGroup: group
                        )
                    )
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var groupHeader: some View {
        HStack(spacing: 8) {
            Button {
                toggleExpanded()
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)

            Image(systemName: "folder")
                .foregroundStyle(.secondary)

            if isRenaming {
                TextField("", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .onSubmit { commitRename() }
                    .onExitCommand { renamingGroupID = nil }
            } else {
                Text(group.name ?? "New Group")
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.04))
        )
        .contentShape(Rectangle())
        .onDrop(of: [paperDragUTI],
                delegate: GroupDropDelegate(viewContext: viewContext, targetGroup: group))
        .contextMenu {
            Button { beginRename() } label: {
                Label("Rename", systemImage: "pencil")
            }

            if level == 0 {
                Button { createSubgroup(group) } label: {
                    Label("New Subgroup", systemImage: "folder.badge.plus")
                }
            }

            Divider()

            Button(role: .destructive) { deleteGroup(group) } label: {
                Label("Delete Group", systemImage: "trash")
            }
        }
    }

    private func toggleExpanded() {
        withAnimation(.snappy(duration: 0.18)) {
            if isExpanded {
                expandedGroups.remove(group.objectID)
                group.isCollapsed = true
            } else {
                expandedGroups.insert(group.objectID)
                group.isCollapsed = false
            }
            try? viewContext.save()
        }
    }

    private func beginRename() {
        renamingGroupID = group.objectID
        renameDraft = group.name ?? ""
    }

    private func commitRename() {
        let v = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        group.name = v.isEmpty ? "New Group" : v
        try? viewContext.save()
        renamingGroupID = nil
    }
}

//
// MARK: - Paper Card Row
//

private struct PaperCardRow: View {
    let paper: Paper
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayTitle(for: paper))
                    .font(.headline)
                    .foregroundStyle(.primary)

                let authorsLine = authorsDisplay(from: paper.authorsJSON)
                if !authorsLine.isEmpty {
                    Text(authorsLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private func displayTitle(for paper: Paper) -> String {
        let short = (paper.shortTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return short.isEmpty ? (paper.title ?? "Untitled") : short
    }

    private func authorsDisplay(from authorsJSON: String?) -> String {
        guard let authorsJSON, let data = authorsJSON.data(using: .utf8) else { return "" }
        guard let authors = try? JSONDecoder().decode([AuthorInput].self, from: data) else { return "" }
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
    }
}

//
// MARK: - Drop Delegates (reuse your existing logic)
//

private struct GroupDropDelegate: DropDelegate {
    let viewContext: NSManagedObjectContext
    let targetGroup: PaperGroup

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [paperDragUTI])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [paperDragUTI]).first else { return false }

        provider.loadItem(forTypeIdentifier: paperDragUTI, options: nil) { item, _ in
            DispatchQueue.main.async {
                let idString: String? = {
                    if let s = item as? String { return s }
                    if let s = item as? NSString { return s as String }
                    if let d = item as? Data { return String(data: d, encoding: .utf8) }
                    return nil
                }()

                guard
                    let idString,
                    let url = URL(string: idString),
                    let objID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
                    let paper = try? viewContext.existingObject(with: objID) as? Paper
                else { return }

                paper.group = targetGroup
                paper.sortIndex = nextSortIndex(in: targetGroup, ctx: viewContext)
                try? viewContext.save()
            }
        }

        return true
    }

    private func nextSortIndex(in group: PaperGroup, ctx: NSManagedObjectContext) -> Int32 {
        let req = NSFetchRequest<Paper>(entityName: "Paper")
        req.predicate = NSPredicate(format: "group == %@", group)
        req.sortDescriptors = [NSSortDescriptor(key: "sortIndex", ascending: false)]
        req.fetchLimit = 1
        let maxExisting = (try? ctx.fetch(req).first?.sortIndex) ?? 0
        return maxExisting + 1
    }
}

private struct PaperReorderDropDelegate: DropDelegate {
    let viewContext: NSManagedObjectContext
    let targetPaper: Paper
    let targetGroup: PaperGroup?

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [paperDragUTI])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [paperDragUTI]).first else { return false }

        provider.loadItem(forTypeIdentifier: paperDragUTI, options: nil) { item, _ in
            DispatchQueue.main.async {
                let idString: String? = {
                    if let s = item as? String { return s }
                    if let s = item as? NSString { return s as String }
                    if let d = item as? Data { return String(data: d, encoding: .utf8) }
                    return nil
                }()

                guard
                    let idString,
                    let url = URL(string: idString),
                    let objID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
                    let moving = try? viewContext.existingObject(with: objID) as? Paper
                else { return }

                moving.group = targetGroup
                moving.sortIndex = targetPaper.sortIndex
                try? viewContext.save()

                renumberPapers(in: viewContext, group: targetGroup)
            }
        }

        return true
    }
}

private func renumberPapers(in ctx: NSManagedObjectContext, group: PaperGroup?) {
    let req = NSFetchRequest<Paper>(entityName: "Paper")
    req.predicate = (group == nil)
        ? NSPredicate(format: "group == nil")
        : NSPredicate(format: "group == %@", group!)
    req.sortDescriptors = [
        NSSortDescriptor(key: "sortIndex", ascending: true),
        NSSortDescriptor(key: "createdAt", ascending: true)
    ]
    guard let items = try? ctx.fetch(req) else { return }

    for (i, p) in items.enumerated() {
        p.sortIndex = Int32(i)
    }
    try? ctx.save()
}
