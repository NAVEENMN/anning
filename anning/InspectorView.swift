import SwiftUI

enum InspectorTab: Hashable {
    case metadata
}

struct InspectorView: View {
    let paper: Paper?
    @State private var tab: InspectorTab = .metadata

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Metadata").tag(InspectorTab.metadata)
            }
            .pickerStyle(.segmented)
            .padding(10)

            Divider()

            Group {
                switch tab {
                case .metadata:
                    MetadataInspectorTab(paper: paper)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct MetadataInspectorTab: View {
    let paper: Paper?

    var body: some View {
        if let paper {
            Form {
                LabeledContent("Title") {
                    Text(paper.title ?? "")
                        .textSelection(.enabled)
                }

                LabeledContent("Short title") {
                    Text(paper.shortTitle ?? "")
                        .textSelection(.enabled)
                }

                LabeledContent("Authors") {
                    Text(authorsDisplay(from: paper.authorsJSON))
                        .textSelection(.enabled)
                }

                LabeledContent("arXiv PDF") {
                    Text(normalizeArxivPDFURL(paper.arxivPDFURL ?? ""))
                        .textSelection(.enabled)
                }

                LabeledContent("Abstract") {
                    Text(paper.abstractText ?? "")
                        .textSelection(.enabled)
                }
            }
        } else {
            Text("Select a paper to see details.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func authorsDisplay(from authorsJSON: String?) -> String {
        guard let authorsJSON, let data = authorsJSON.data(using: .utf8) else { return "" }
        do {
            let authors = try JSONDecoder().decode([AuthorInput].self, from: data)
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
        } catch {
            return ""
        }
    }
}
