import SwiftUI
import CoreData

struct AddEventView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let eventToEdit: Event?

    @State private var date: Date = Date()
    @State private var shortTitle: String = ""
    @State private var summaryText: String = ""   // description
    @State private var eventType: EventType = .informative
    @State private var url: String = ""
    @State private var errorMessage: String?

    init(eventToEdit: Event? = nil) {
        self.eventToEdit = eventToEdit
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date])

                    TextField("Short title", text: $shortTitle)

                    Picker("Event type", selection: $eventType) {
                        ForEach(EventType.allCases) { t in
                            Label(t.displayName, systemImage: t.systemImage).tag(t)
                        }
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $summaryText)
                            .frame(minHeight: 140)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.25))
                            )
                    }
                    .padding(.top, 4)

                    TextField("URL (optional)", text: $url)
                        .autocorrectionDisabled()
                } header: {
                    Text(eventToEdit == nil ? "Add Event" : "Edit Event")
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
                Button(eventToEdit == nil ? "Save" : "Update") { saveOrUpdate() }
                    .disabled(shortTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              summaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { loadIfEditing() }
        .onChange(of: eventToEdit?.objectID) {
            loadIfEditing()
        }
    }

    private func loadIfEditing() {
        guard let e = eventToEdit else { return }
        date = e.date ?? Date()
        shortTitle = e.shortTitle ?? ""
        summaryText = e.summaryText ?? ""
        eventType = eventTypeFromStored(e.eventType)
        url = e.url ?? ""
    }

    private func saveOrUpdate() {
        errorMessage = nil

        let st = shortTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !st.isEmpty else { errorMessage = "Short title is required."; return }
        guard !desc.isEmpty else { errorMessage = "Description is required."; return }
        if !u.isEmpty, URL(string: u) == nil {
            errorMessage = "URL is not valid (or leave it empty)."
            return
        }

        let e: Event
        if let existing = eventToEdit {
            e = existing
        } else {
            e = Event(context: viewContext)
            e.id = UUID()
            e.createdAt = Date()
        }

        e.date = date
        e.shortTitle = st
        e.summaryText = desc
        e.eventType = eventType.rawValue
        e.url = u.isEmpty ? nil : u

        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
}
