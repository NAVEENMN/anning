import SwiftUI
import CoreData
import AppKit

// Shared with ContentView
enum SettingsSection: Hashable {
    case account
    case general
}

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var selection: SettingsSection

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \AppSettings.createdAt, ascending: true)],
        animation: .default
    )
    private var settings: FetchedResults<AppSettings>

    private var s: AppSettings? { settings.first }

    @State private var nameDraft = ""
    @State private var emailDraft = ""
    @State private var bskyDraft = ""
    @State private var savePathDraft = ""

    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, email, bsky, savePath }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch selection {
                case .account:
                    accountPane
                case .general:
                    generalPane
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            ensureSettingsRow()
            loadDrafts()
        }
        .onChange(of: settings.count) {
            ensureSettingsRow()
            loadDrafts()
        }
        .onChange(of: focusedField) {
            if focusedField == nil { persist() }
        }
    }

    private var accountPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                TextField("Name", text: $nameDraft)
                    .focused($focusedField, equals: .name)

                TextField("Email", text: $emailDraft)
                    .focused($focusedField, equals: .email)

                TextField("bsky", text: $bskyDraft)
                    .focused($focusedField, equals: .bsky)
            }
            .frame(maxWidth: 560)
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                HStack(spacing: 10) {
                    TextField("Save path", text: $savePathDraft)
                        .focused($focusedField, equals: .savePath)

                    Button { chooseSaveDirectory() } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Choose save directory")
                }
            }
            .frame(maxWidth: 560)
        }
    }

    private func ensureSettingsRow() {
        if s == nil {
            let obj = AppSettings(context: viewContext)
            obj.id = UUID()
            obj.createdAt = Date()
            obj.name = ""
            obj.email = ""
            obj.bsky = ""
            obj.defaultSavePath = ""
            try? viewContext.save()
        }
    }

    private func loadDrafts() {
        guard let s else { return }
        nameDraft = s.name ?? ""
        emailDraft = s.email ?? ""
        bskyDraft = s.bsky ?? ""
        savePathDraft = s.defaultSavePath ?? ""
    }

    private func persist() {
        guard let s else { return }
        s.name = nameDraft
        s.email = emailDraft
        s.bsky = bskyDraft
        s.defaultSavePath = savePathDraft
        try? viewContext.save()
    }

    private func chooseSaveDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose Save Directory"

        if panel.runModal() == .OK, let url = panel.url {
            savePathDraft = url.path
            persist()
        }
    }
}
