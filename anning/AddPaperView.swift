import SwiftUI
import CoreData

struct AddPaperView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// If non-nil, we are editing an existing paper (we'll re-fetch from server on Update).
    let paperToEdit: Paper?

    @State private var arxivPDFURL: String = ""
    @State private var errorMessage: String?

    @State private var isBusy: Bool = false
    @State private var statusText: String = ""

    init(paperToEdit: Paper? = nil) {
        self.paperToEdit = paperToEdit
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Paper") {
                    TextField("arXiv PDF URL (https://arxiv.org/pdf/<id>.pdf)", text: $arxivPDFURL)
                        .autocorrectionDisabled()
                }

                if isBusy {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(statusText.isEmpty ? "Fetching paper details…" : statusText)
                                .foregroundStyle(.secondary)
                        }
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
                    .disabled(isBusy)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(paperToEdit == nil ? "Save" : "Update") {
                    Task { await saveOrUpdateFromServer() }
                }
                .disabled(isBusy || arxivPDFURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { loadIfEditing() }
    }

    private func loadIfEditing() {
        guard let p = paperToEdit else { return }
        arxivPDFURL = p.arxivPDFURL ?? ""
    }

    private func saveOrUpdateFromServer() async {
        errorMessage = nil

        let normalized = normalizeArxivPDFURL(arxivPDFURL)
        let cleanedURL = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedURL.isEmpty else {
            errorMessage = "arXiv PDF URL is required."
            return
        }
        guard isValidArxivPDFURL(cleanedURL) else {
            errorMessage = "Only arXiv PDF URLs are accepted for now. Use: https://arxiv.org/pdf/<id>.pdf"
            return
        }

        await MainActor.run {
            isBusy = true
            statusText = "Contacting server…"
        }

        do {
            let payload = try await PaperDetailsAPI.fetchPaperDetails(pdfURL: cleanedURL)

            await MainActor.run {
                statusText = "Saving to database…"
            }

            try await MainActor.run {
                let paper: Paper
                let isEditing = (paperToEdit != nil)

                if let existing = paperToEdit {
                    paper = existing
                } else {
                    paper = Paper(context: viewContext)
                    paper.id = UUID()
                    paper.createdAt = Date()
                    paper.sortIndex = Int32(Int(Date().timeIntervalSince1970))
                    paper.group = nil
                }

                // If URL changed, clear cached PDF
                if isEditing {
                    let prev = normalizeArxivPDFURL(paper.arxivPDFURL ?? "")
                    if prev != cleanedURL {
                        if let path = paper.localPDFPath, FileManager.default.fileExists(atPath: path) {
                            try? FileManager.default.removeItem(atPath: path)
                        }
                        paper.localPDFPath = nil
                    }
                }

                applyServerPaper(payload.paper, to: paper)

                try viewContext.save()
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }

        await MainActor.run {
            isBusy = false
            statusText = ""
        }
    }

    // MARK: - Mapping server -> Core Data

    private func applyServerPaper(_ s: PaperDetailsAPI.PaperInfo, to paper: Paper) {
        paper.arxivPDFURL = s.pdf_url

        let title = (s.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        paper.title = title.isEmpty ? "Untitled" : title
        paper.shortTitle = paper.title // you can add a better short-title heuristic later

        // Abstract: store as RTF-base64 so it renders "formatted" in your RichText editor box.
        let abs = (s.abstract ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        paper.abstractText = RichTextStorage.encodeRTFBase64(NSAttributedString(string: abs))

        // Authors: turn "A, B, C" into authorsJSON
        paper.authorsJSON = encodeAuthorsJSON(from: s.authors)

        // Paper type: keep default empirical work for now
        if (paper.paperType ?? "").isEmpty {
            paper.paperType = PaperType.empiricalWork.rawValue
        }

        // Seed notes JSON sections (only fill if empty so user edits don't get overwritten on Update)
        var notes = decodeNotes(from: paper.notesJSON)

        setIfEmpty(&notes, key: NotesSection.motivation.rawValue, value: s.motivation)
        setIfEmpty(&notes, key: NotesSection.experimentSetup.rawValue, value: s.experiment_setup)
        setIfEmpty(&notes, key: NotesSection.experimentMethod.rawValue, value: s.methodology)
        setIfEmpty(&notes, key: NotesSection.results.rawValue, value: s.result)
        setIfEmpty(&notes, key: NotesSection.conclusion.rawValue, value: s.conclusion)

        if let survey = s.survey, survey.lowercased() != "n/a" {
            setIfEmpty(&notes, key: NotesSection.surveyDetails.rawValue, value: survey)
        }

        // Store server metadata (and embedding) without changing Core Data schema
        if let meta = try? JSONEncoder().encode(s),
           let metaStr = String(data: meta, encoding: .utf8) {
            notes["_server_paper_json"] = metaStr
        }

        if let emb = s.embedding_vector,
           let data = try? JSONEncoder().encode(emb),
           let embStr = String(data: data, encoding: .utf8) {
            notes["_embedding_vector_json"] = embStr
        }

        paper.notesJSON = encodeNotes(notes)
    }

    private func encodeAuthorsJSON(from authorsCSV: String?) -> String {
        let raw = (authorsCSV ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "[]" }

        let names = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let arr = names.map { AuthorInput(firstName: "", lastName: $0) } // simplest + safe

        if let data = try? JSONEncoder().encode(arr),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "[]"
    }

    private func decodeNotes(from json: String?) -> [String: String] {
        guard
            let json,
            let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data),
            let dict = obj as? [String: String]
        else { return [:] }
        return dict
    }

    private func encodeNotes(_ dict: [String: String]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: dict, options: [])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    private func setIfEmpty(_ dict: inout [String: String], key: String, value: String?) {
        let v = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        let existing = (dict[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty { dict[key] = v }
    }
}
