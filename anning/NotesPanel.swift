import SwiftUI
import CoreData

enum NotesSection: String, CaseIterable, Identifiable {
    case history
    case motivation
    case surveyDetails
    case experimentSetup
    case experimentMethod
    case results
    case theory
    case formalProof
    case limitations
    case conclusion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: return "History"
        case .motivation: return "Motivation"
        case .surveyDetails: return "Survey Details"
        case .experimentSetup: return "Experiment Setup"
        case .experimentMethod: return "Experiment Method"
        case .results: return "Results"
        case .theory: return "Theory"
        case .formalProof: return "Formal Proof"
        case .limitations: return "Limitations"
        case .conclusion: return "Conclusion"
        }
    }

    var systemImage: String {
        switch self {
        case .history: return "clock"
        case .motivation: return "lightbulb"
        case .surveyDetails: return "list.bullet.rectangle"
        case .experimentSetup: return "slider.horizontal.3"
        case .experimentMethod: return "wrench.and.screwdriver"
        case .results: return "chart.xyaxis.line"
        case .theory: return "function"
        case .formalProof: return "checkmark.shield"
        case .limitations: return "exclamationmark.triangle"
        case .conclusion: return "checkmark.seal"
        }
    }
}

func sectionsForPaperType(_ type: PaperType) -> [NotesSection] {
    switch type {
    case .empiricalWork:
        return [.history, .motivation, .experimentSetup, .experimentMethod, .results, .limitations, .conclusion]
    case .surveyPaper:
        return [.history, .motivation, .surveyDetails, .limitations, .conclusion]
    case .theoreticalProof:
        return [.history, .motivation, .theory, .formalProof, .limitations, .conclusion]
    }
}

struct NotesPanel: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var paper: Paper

    @State private var selected: NotesSection = .history
    @State private var notes: [String: String] = [:]

    private var type: PaperType { paperTypeFromStored(paper.paperType) }
    private var availableSections: [NotesSection] { sectionsForPaperType(type) }

    var body: some View {
        VStack(spacing: 0) {
            // Xcode-like tab strip (icons)
            HStack(spacing: 6) {
                ForEach(Array(availableSections.enumerated()), id: \.element.id) { idx, section in
                    Button {
                        selected = section
                    } label: {
                        Image(systemName: section.systemImage)
                            .foregroundStyle(selected == section ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selected == section ? Color.secondary.opacity(0.25) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(section.title)

                    if idx != availableSections.count - 1 {
                        Divider().frame(height: 16)
                    }
                }

                Spacer()

                Text(selected.title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(10)

            Divider()

            MarkdownEditorBox(
                text: binding(for: selected),
                placeholder: "Write notes for \(selected.title)…",
                minHeight: 220,
                maxHeight: 500
            )
            .padding(10)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            loadFromPaper()
            ensureSelectedIsValid()
        }
        .onChange(of: paper.objectID) {
            loadFromPaper()
            ensureSelectedIsValid()
        }
        .onChange(of: paper.paperType) {
            ensureSelectedIsValid()
        }
    }

    private func ensureSelectedIsValid() {
        if !availableSections.contains(selected) {
            selected = availableSections.first ?? .history
        }
    }

    private func binding(for section: NotesSection) -> Binding<String> {
        Binding(
            get: { notes[section.rawValue] ?? "" },
            set: { newValue in
                notes[section.rawValue] = newValue
                persistToPaper()
            }
        )
    }

    private func loadFromPaper() {
        notes = decodeNotes(from: paper.notesJSON)
    }

    private func persistToPaper() {
        paper.notesJSON = encodeNotes(notes)
        do {
            try viewContext.save()
        } catch {
            print("Failed to save notes:", error)
        }
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
}
