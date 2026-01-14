import SwiftUI
import CoreData
import AppKit
import FirebaseAuth

// Shared with ContentView
enum SettingsSection: Hashable {
    case account
    case general
}

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var auth: AuthViewModel
    @Binding var selection: SettingsSection

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \AppSettings.createdAt, ascending: true)],
        animation: .default
    )
    private var settings: FetchedResults<AppSettings>

    private var s: AppSettings? { settings.first }

    @State private var nameDraft = ""
    @State private var emailDraft = ""
    @State private var savePathDraft = ""

    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, email, savePath }

    private var appVersionLabel: String {
        let v = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
        return "Anning v\(v)"
    }

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
        let user = Auth.auth().currentUser
        let name = user?.displayName ?? ""
        let email = user?.email ?? ""

        return VStack(alignment: .leading, spacing: 12) {
            Text("Account")
                .font(.title2)
                .fontWeight(.semibold)

            Form {
                LabeledContent("Name") {
                    Text(name.isEmpty ? "—" : name)
                        .textSelection(.enabled)
                }
                
                LabeledContent("Email") {
                    Text(email.isEmpty ? "—" : email)
                        .textSelection(.enabled)
                }
                
                LabeledContent("User ID") {
                    Text(user?.uid ?? "—")
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                }
            }
            .frame(maxWidth: 560)

            HStack {
                Spacer()
                Button(role: .destructive) {
                    auth.signOut()
                } label: {
                    Text("Log out")
                }
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
                LabeledContent("Version") {
                    Text(appVersionLabel)
                        .foregroundStyle(.secondary)
                }

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
        savePathDraft = s.defaultSavePath ?? ""
    }

    private func persist() {
        guard let s else { return }
        // name and email now come from Firebase, only persist local settings
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
