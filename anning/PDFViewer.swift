import SwiftUI
import PDFKit
import CoreData

/// SwiftUI wrapper around PDFKit's PDFView (macOS)
struct PDFKitView: NSViewRepresentable {
    let document: PDFDocument?

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.displaysPageBreaks = true
        v.backgroundColor = .clear
        return v
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = document
    }
}

/// Cached PDF viewer that stores PDFs locally in Application Support
struct PaperPDFViewer: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var paper: Paper

    @State private var document: PDFDocument?
    @State private var isLoading = false
    @State private var errorMessage: String?

    // prevents reload loops
    @State private var lastLoadedKey: String? = nil

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading PDF…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 260)

            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't load PDF")
                        .font(.headline)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)

            } else if let document {
                PDFKitView(document: document)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                Text("No PDF loaded.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
        .task(id: taskKey) {
            await loadPDFIfNeeded()
        }
    }

    private var taskKey: String {
        let url = normalizeArxivPDFURL(paper.arxivPDFURL ?? "")
        return "\(paper.objectID.uriRepresentation().absoluteString)::\(url)"
    }

    private func loadPDFIfNeeded() async {
        if lastLoadedKey == taskKey, document != nil, errorMessage == nil {
            return
        }
        await loadPDF()
    }

    private func loadPDF() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            if lastLoadedKey != taskKey {
                document = nil
            }
        }

        let remoteString = normalizeArxivPDFURL(paper.arxivPDFURL ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !remoteString.isEmpty, let remoteURL = URL(string: remoteString) else {
            await MainActor.run {
                isLoading = false
                errorMessage = "Missing/invalid PDF URL."
                lastLoadedKey = taskKey
            }
            return
        }

        // Ensure paper.id exists so cache filename is stable
        let paperID: UUID = await MainActor.run {
            if let id = paper.id { return id }
            let id = UUID()
            paper.id = id
            do { try viewContext.save() }
            catch { print("Failed to save paper.id:", error) }
            return id
        }

        let expectedURL: URL
        do {
            expectedURL = try PDFCache.destinationURL(paperID: paperID)
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "Cache directory error: \(error.localizedDescription)"
                lastLoadedKey = taskKey
            }
            return
        }

        // 1) If localPDFPath exists and is readable, load it
        let storedPath = await MainActor.run { paper.localPDFPath }
        if let storedPath, PDFCache.fileExists(storedPath) {
            let localURL = URL(fileURLWithPath: storedPath)
            if let doc = PDFDocument(url: localURL) {
                await MainActor.run {
                    isLoading = false
                    document = doc
                    lastLoadedKey = taskKey
                }
                return
            } else {
                await MainActor.run {
                    paper.localPDFPath = nil
                    do { try viewContext.save() }
                    catch { print("Failed to clear localPDFPath:", error) }
                }
            }
        }

        // 2) If deterministic cache exists, use it
        if PDFCache.fileExists(at: expectedURL), let doc = PDFDocument(url: expectedURL) {
            await MainActor.run {
                paper.localPDFPath = expectedURL.path
                do { try viewContext.save() }
                catch { print("Failed to save localPDFPath:", error) }

                isLoading = false
                document = doc
                lastLoadedKey = taskKey
            }
            return
        }

        // 3) Download and cache
        do {
            let (data, response) = try await URLSession.shared.data(from: remoteURL)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw NSError(domain: "PDFDownload", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "HTTP error"])
            }

            try data.write(to: expectedURL, options: .atomic)

            guard let doc = PDFDocument(url: expectedURL) else {
                throw NSError(domain: "PDFDownload", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Downloaded file is not a valid PDF"])
            }

            await MainActor.run {
                paper.localPDFPath = expectedURL.path
                do { try viewContext.save() }
                catch { print("Failed to save localPDFPath:", error) }

                isLoading = false
                document = doc
                lastLoadedKey = taskKey
            }

        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                lastLoadedKey = taskKey
            }
        }
    }
}
