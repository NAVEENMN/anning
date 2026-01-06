import SwiftUI
import CoreData

struct AddPaperView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// If non-nil, we are editing an existing paper.
    let paperToEdit: Paper?

    @State private var title: String = ""
    @State private var shortTitle: String = ""
    @State private var abstractText: String = ""
    @State private var arxivPDFURL: String = ""
    @State private var paperType: PaperType = .empiricalWork
    @State private var authors: [AuthorInput] = [AuthorInput(firstName: "", lastName: "")]
    @State private var errorMessage: String?

    init(paperToEdit: Paper? = nil) {
        self.paperToEdit = paperToEdit
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Paper title", text: $title)
                    TextField("Short title (max 5 words)", text: $shortTitle)

                    Picker("Type", selection: $paperType) {
                        ForEach(PaperType.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("arXiv PDF URL (https://arxiv.org/pdf/<id>.pdf)", text: $arxivPDFURL)
                        .autocorrectionDisabled()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Abstract")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $abstractText)
                            .frame(minHeight: 180)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.25))
                            )
                    }
                    .padding(.top, 4)
                } header: {
                    Text("Paper")
                }

                Section {
                    HStack {
                        Text("Authors")
                        Spacer()
                        Button {
                            authors.append(AuthorInput(firstName: "", lastName: ""))
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Add author")
                    }

                    ForEach($authors) { $author in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Last name", text: $author.lastName)
                                TextField("First name", text: $author.firstName)
                            }

                            Spacer()

                            Button {
                                deleteAuthor(author.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove author")
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(paperToEdit == nil ? "Save" : "Update") { saveOrUpdate() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { loadIfEditing() }
    }

    private func loadIfEditing() {
        guard let p = paperToEdit else { return }

        title = p.title ?? ""
        shortTitle = p.shortTitle ?? ""
        abstractText = p.abstractText ?? ""
        arxivPDFURL = p.arxivPDFURL ?? ""
        paperType = paperTypeFromStored(p.paperType)

        if let json = p.authorsJSON, let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([AuthorInput].self, from: data),
           !decoded.isEmpty {
            authors = decoded
        } else {
            authors = [AuthorInput(firstName: "", lastName: "")]
        }
    }

    private func deleteAuthor(_ id: UUID) {
        authors.removeAll { $0.id == id }
        if authors.isEmpty {
            authors = [AuthorInput(firstName: "", lastName: "")]
        }
    }

    private func saveOrUpdate() {
        errorMessage = nil

        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedShort = shortTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedAbstract = abstractText.trimmingCharacters(in: .whitespacesAndNewlines)

        // arXiv only
        let normalizedURL = normalizeArxivPDFURL(arxivPDFURL)
        let cleanedURL = normalizedURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedTitle.isEmpty else {
            errorMessage = "Paper title is required."
            return
        }

        if !cleanedShort.isEmpty {
            let wordCount = cleanedShort.split { $0.isWhitespace || $0.isNewline }.count
            if wordCount > 5 {
                errorMessage = "Short title must be 5 words or fewer."
                return
            }
        }

        guard !cleanedURL.isEmpty else {
            errorMessage = "arXiv PDF URL is required (arXiv-only for now)."
            return
        }

        guard isValidArxivPDFURL(cleanedURL) else {
            errorMessage = "Only arXiv PDF URLs are accepted for now. Use: https://arxiv.org/pdf/<id>.pdf"
            return
        }

        let cleanedAuthors = authors
            .map {
                AuthorInput(
                    id: $0.id,
                    firstName: $0.firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                    lastName: $0.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
            .filter { !$0.firstName.isEmpty || !$0.lastName.isEmpty }

        let authorsJSON: String
        do {
            let data = try JSONEncoder().encode(cleanedAuthors)
            authorsJSON = String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            errorMessage = "Failed to encode authors."
            return
        }

        withAnimation {
            let paper: Paper
            let isEditing = (paperToEdit != nil)

            if let existing = paperToEdit {
                paper = existing
            } else {
                paper = Paper(context: viewContext)
                paper.id = UUID()
                paper.createdAt = Date()
            }

            // If editing and URL changed, invalidate cached PDF
            if isEditing {
                let previousURL = normalizeArxivPDFURL(paper.arxivPDFURL ?? "")
                if previousURL != cleanedURL {
                    if let path = paper.localPDFPath, FileManager.default.fileExists(atPath: path) {
                        try? FileManager.default.removeItem(atPath: path)
                    }
                    paper.localPDFPath = nil
                }
            }

            paper.title = cleanedTitle
            paper.shortTitle = cleanedShort
            paper.abstractText = cleanedAbstract
            paper.arxivPDFURL = cleanedURL
            paper.paperType = paperType.rawValue
            paper.authorsJSON = authorsJSON

            do {
                try viewContext.save()
                dismiss()
            } catch {
                let nsError = error as NSError
                errorMessage = "Save failed: \(nsError.localizedDescription)"
            }
        }
    }
}
