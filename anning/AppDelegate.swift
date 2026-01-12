import AppKit
import CoreData

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var lastProjectURL: URL? {
        get {
            guard let s = UserDefaults.standard.string(forKey: "lastProjectURL") else { return nil }
            return URL(fileURLWithPath: s)
        }
        set {
            UserDefaults.standard.setValue(newValue?.path, forKey: "lastProjectURL")
        }
    }

    private var lastProjectTitle: String {
        get { UserDefaults.standard.string(forKey: "lastProjectTitle") ?? "anning-project" }
        set { UserDefaults.standard.setValue(newValue, forKey: "lastProjectTitle") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.bootstrapLaunch()
        }
    }

    private func bootstrapLaunch() {
        let ctx = PersistenceController.shared.container.viewContext

        let req = NSFetchRequest<Workspace>(entityName: "Workspace")
        req.fetchLimit = 1
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        let ws = (try? ctx.fetch(req))?.first
        let title = (ws?.projectTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // If a project already exists in the DB, continue where you left off (IDE-like)
        if !title.isEmpty {
            NotificationCenter.default.post(name: .anningProjectDidLoad, object: nil)
            updateWindowTitle(title)
            return
        }

        // Otherwise, first-time setup: require Open/New
        promptOpenOnLaunch()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Always ask on quit (Save / Don't Save / Cancel)
        promptSaveOnQuit(sender: sender)
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Menu actions

    @discardableResult
    func menuNewProject() -> Bool {
        return newProjectDialog(required: false)
    }

    @discardableResult
    func menuOpenProject() -> Bool {
        return openProjectPanel(required: false)
    }

    @discardableResult
    func menuSave() -> Bool {
        // Save = overwrite if we already have a path; otherwise behaves like Save As
        if let url = lastProjectURL {
            return writeProject(to: url)
        } else {
            var ok = false
            saveProjectPanel { ok = $0 }
            return ok
        }
    }

    @discardableResult
    func menuSaveAs() -> Bool {
        var ok = false
        saveProjectPanel { ok = $0 }
        return ok
    }

    // MARK: - UI prompts

    private func promptOpenOnLaunch() {
        let alert = NSAlert()
        alert.messageText = "Start a project"
        alert.informativeText = "You must open an existing project or create a new one."
        alert.addButton(withTitle: "Open Project…")
        alert.addButton(withTitle: "New Project…")
        alert.addButton(withTitle: "Quit")

        let choice = alert.runModal()

        if choice == .alertFirstButtonReturn {
            if !openProjectPanel(required: true) { NSApp.terminate(nil) }
        } else if choice == .alertSecondButtonReturn {
            if !newProjectDialog(required: true) { NSApp.terminate(nil) }
        } else {
            NSApp.terminate(nil)
        }
    }

    private func openProjectPanel(required: Bool) -> Bool {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Open Project"
        panel.message = "Select a project .json file"

        if let last = lastProjectURL {
            panel.directoryURL = last.deletingLastPathComponent()
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            // required=true: cancel means failure; required=false: cancel is a no-op (return true)
            return !required
        }

        do {
            let ctx = PersistenceController.shared.container.viewContext
            let data = try Data(contentsOf: url)
            try ProjectIO.importJSON(data: data, context: ctx)
            lastProjectURL = url

            // Fetch project title from imported workspace
            let req = NSFetchRequest<Workspace>(entityName: "Workspace")
            req.fetchLimit = 1
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            let ws = try ctx.fetch(req).first
            let title = ws?.projectTitle ?? url.deletingPathExtension().lastPathComponent
            lastProjectTitle = title

            NotificationCenter.default.post(name: .anningProjectDidLoad, object: nil)
            DispatchQueue.main.async { self.updateWindowTitle(title) }
            return true
        } catch {
            showError("Failed to open project", error)
            return false
        }
    }

    private func newProjectDialog(required: Bool) -> Bool {
        while true {
            let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 190))

            let titleLabel = NSTextField(labelWithString: "Project Title (required)")
            titleLabel.textColor = .secondaryLabelColor
            titleLabel.frame = NSRect(x: 0, y: 160, width: 360, height: 18)

            let titleField = NSTextField(string: "")
            titleField.placeholderString = "e.g., Attention Mechanisms"
            titleField.frame = NSRect(x: 0, y: 130, width: 360, height: 24)

            let objLabel = NSTextField(labelWithString: "Research Objective (required)")
            objLabel.textColor = .secondaryLabelColor
            objLabel.frame = NSRect(x: 0, y: 104, width: 360, height: 18)

            let objectiveView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 80))
            objectiveView.isRichText = false
            objectiveView.font = NSFont.systemFont(ofSize: 13)
            objectiveView.string = ""

            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 96))
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            scroll.documentView = objectiveView

            accessory.addSubview(titleLabel)
            accessory.addSubview(titleField)
            accessory.addSubview(objLabel)
            accessory.addSubview(scroll)

            let alert = NSAlert()
            alert.messageText = "New Project"
            alert.informativeText = "Enter a title and research objective."
            alert.accessoryView = accessory
            alert.addButton(withTitle: "Create")
            alert.addButton(withTitle: "Cancel")

            let res = alert.runModal()
            if res != .alertFirstButtonReturn {
                // required=true: cancel means failure; required=false: cancel is a no-op
                return !required
            }

            let projectTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let objective = objectiveView.string.trimmingCharacters(in: .whitespacesAndNewlines)

            if projectTitle.isEmpty || objective.isEmpty {
                let a = NSAlert()
                a.messageText = "Missing fields"
                a.informativeText = "Both Project Title and Research Objective are required."
                a.addButton(withTitle: "OK")
                a.runModal()
                continue
            }

            do {
                let ctx = PersistenceController.shared.container.viewContext
                try ProjectIO.resetDatabase(context: ctx)

                let w = Workspace(context: ctx)
                w.id = UUID()
                w.createdAt = Date()
                w.projectTitle = projectTitle
                w.researchObjective = objective
                try ctx.save()

                lastProjectTitle = projectTitle
                lastProjectURL = nil

                NotificationCenter.default.post(name: .anningProjectDidLoad, object: nil)
                DispatchQueue.main.async { self.updateWindowTitle(projectTitle) }
                return true
            } catch {
                showError("Failed to create project", error)
                return false
            }
        }
    }

    private func promptSaveOnQuit(sender: NSApplication) {
        let alert = NSAlert()
        alert.messageText = "Do you want to save your project before quitting?"
        alert.informativeText = "Your data is stored in the database. Saving exports it to a .json project file."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        let choice = alert.runModal()

        switch choice {
        case .alertFirstButtonReturn: // Save
            saveProjectPanel { [weak self] ok in
                sender.reply(toApplicationShouldTerminate: ok)
                _ = self
            }
        case .alertSecondButtonReturn: // Don't Save
            sender.reply(toApplicationShouldTerminate: true)
        default: // Cancel
            sender.reply(toApplicationShouldTerminate: false)
        }
    }

    private func saveProjectPanel(completion: @escaping (Bool) -> Void) {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["json"]
        panel.canCreateDirectories = true
        panel.title = "Save Project"
        panel.message = "Choose where to save your project .json file"
        panel.isExtensionHidden = false

        if let last = lastProjectURL {
            panel.directoryURL = last.deletingLastPathComponent()
            panel.nameFieldStringValue = last.deletingPathExtension().lastPathComponent
        } else {
            panel.nameFieldStringValue = lastProjectTitle
            
            // Use global default save directory if set
            let ctx = PersistenceController.shared.container.viewContext
            let req = NSFetchRequest<AppSettings>(entityName: "AppSettings")
            req.fetchLimit = 1
            req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
            if let s = try? ctx.fetch(req).first,
               let path = s.defaultSavePath,
               !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
            }
        }

        if panel.runModal() == .OK, let url = panel.url {
            completion(writeProject(to: url))
        } else {
            completion(false)
        }
    }

    private func writeProject(to url: URL) -> Bool {
        do {
            let ctx = PersistenceController.shared.container.viewContext
            let data = try ProjectIO.exportJSON(context: ctx)
            try data.write(to: url, options: [.atomic])
            lastProjectURL = url
            lastProjectTitle = url.deletingPathExtension().lastPathComponent
            return true
        } catch {
            showError("Failed to save project", error)
            return false
        }
    }

    private func showError(_ title: String, _ error: Error) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = error.localizedDescription
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    private func showSimpleMessage(_ title: String, _ msg: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = msg
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    private func updateWindowTitle(_ title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let final = t.isEmpty ? "anning" : t
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.mainWindow?.title = final
            NSApp.keyWindow?.title = final
        }
    }
}

extension Notification.Name {
    static let anningProjectDidLoad = Notification.Name("anningProjectDidLoad")
}
