import SwiftUI
import CoreData

struct EventInspectorView: View {
    @Environment(\.managedObjectContext) private var viewContext
    let event: Event?

    var body: some View {
        if let event {
            Form {
                LabeledContent("Date") {
                    Text(dateOnlyFormatter.string(from: event.date ?? Date()))
                }

                LabeledContent("Type") {
                    let t = eventTypeFromStored(event.eventType)
                    Label(t.displayName, systemImage: t.systemImage)
                }

                LabeledContent("Short title") {
                    Text(event.shortTitle ?? "")
                        .textSelection(.enabled)
                }

                if let url = event.url, !url.isEmpty, let link = URL(string: url) {
                    LabeledContent("URL") {
                        Link("Link", destination: link)
                    }
                }

                Section("Description") {
                    TextEditor(text: descriptionBinding(for: event))
                        .frame(minHeight: 260)
                }
            }
        } else {
            Color.clear
        }
    }

    private func descriptionBinding(for event: Event) -> Binding<String> {
        Binding(
            get: { event.summaryText ?? "" },
            set: { newValue in
                event.summaryText = newValue
                do { try viewContext.save() }
                catch { print("Failed to save description:", error) }
            }
        )
    }
}

private let dateOnlyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .none
    return f
}()
