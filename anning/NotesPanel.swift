import SwiftUI
import CoreData

enum NotesSection: String, CaseIterable, Identifiable {
    case history
    case motivation
    case experimentSetup
    case experimentMethod
    case results
    case conclusion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: return "History"
        case .motivation: return "Motivation"
        case .experimentSetup: return "Experiment Setup"
        case .experimentMethod: return "Experiment Method"
        case .results: return "Results"
        case .conclusion: return "Conclusion"
        }
    }

    var systemImage: String {
        switch self {
        case .history: return "clock"
        case .motivation: return "lightbulb"
        case .experimentSetup: return "slider.horizontal.3"
        case .experimentMethod: return "wrench.and.screwdriver"
        case .results: return "chart.xyaxis.line"
        case .conclusion: return "checkmark.seal"
        }
    }

    var placeholder: String {
        "Write notes for \(title)…"
    }
}

struct NotesPanel: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var paper: Paper

    @State private var selected: NotesSection = .history
    @State private var notes: [String: String] = [:]
    @State private var didLoad = false

    var body: some View {
        VStack(spacing: 0) {
            // Tabs row (like Xcode bottom pane)
            HStack(spacing: 8) {
                Picker("", selection: $selected) {
                    ForEach(NotesSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)

                Spacer()
            }
            .padding(10)

            Divider()

            ZStack(alignment: .topLeading) {
                TextEditor(text: binding(for: selected))
                    .font(.body)
                    .padding(10)

                if binding(for: selected).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(selected.placeholder)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { loadIfNeeded() }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        notes = decodeNotes(from: paper.notesJSON)
    }

    private func binding(for section: NotesSection) -> Binding<String> {
        Binding(
            get: { notes[section.rawValue] ?? "" },
            set: { newValue in
                notes[section.rawValue] = newValue
                persistNotes()
            }
        )
    }

    private func persistNotes() {
        paper.notesJSON = encodeNotes(notes)
        do {
            try viewContext.save()
        } catch {
            // keep UI responsive; you can add error UI later if desired
            print("Failed to save notes:", error)
        }
    }

    private func decodeNotes(from json: String?) -> [String: String] {
        guard
            let json,
            let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data),
            let dict = obj as? [String: String]
        else {
            return [:]
        }
        return dict
    }

    private func encodeNotes(_ dict: [String: String]) -> String {
        let data = try? JSONSerialization.data(withJSONObject: dict, options: [])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

