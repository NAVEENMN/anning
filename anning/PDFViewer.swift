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

/// Downloads a remote PDF (or loads local file URL) and displays it using PDFKit.
struct PDFRemoteViewer: View {
    let urlString: String

    @State private var document: PDFDocument?
    @State private var isLoading = false
    @State private var errorMessage: String?

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
                    .frame(maxWidth: .infinity, minHeight: 500)
            } else {
                Text("No PDF loaded.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 260)
            }
        }
        .onAppear {
            loadIfNeeded()
        }
        .onChange(of: urlString) {
            document = nil
            errorMessage = nil
            isLoading = false
            loadIfNeeded()
        }
    }

    private func loadIfNeeded() {
        guard document == nil, !isLoading else { return }

        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            errorMessage = "Invalid URL: \(trimmed)"
            return
        }

        // Local file URL support
        if url.isFileURL {
            if let doc = PDFDocument(url: url) {
                document = doc
            } else {
                errorMessage = "Failed to open local PDF."
            }
            return
        }

        // Remote URL: download the bytes, then build PDFDocument(data:)
        isLoading = true
        errorMessage = nil

        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 60)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false

                if let error {
                    errorMessage = error.localizedDescription
                    return
                }

                guard let http = response as? HTTPURLResponse else {
                    errorMessage = "No HTTP response."
                    return
                }

                guard (200...299).contains(http.statusCode) else {
                    errorMessage = "HTTP \(http.statusCode)"
                    return
                }

                guard let data, !data.isEmpty else {
                    errorMessage = "Empty response."
                    return
                }

                guard let doc = PDFDocument(data: data) else {
                    errorMessage = "Response was not a valid PDF."
                    return
                }

                document = doc
            }
        }.resume()
    }
}

/// Cached PDF viewer that stores PDFs locally in Application Support
struct PaperPDFViewer: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var paper: Paper

    @State private var document: PDFDocument?
    @State private var isLoading = false
    @State private var errorMessage: String?

    // NEW: prevents reloading loops when SwiftUI recreates the view/task
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

    // Keep key stable and based only on what should trigger a reload
    private var taskKey: String {
        let url = normalizeArxivPDFURL(paper.arxivPDFURL ?? "")
        return "\(paper.objectID.uriRepresentation().absoluteString)::\(url)"
    }

    private func loadPDFIfNeeded() async {
        // If we already loaded for this key and still have a document, do nothing.
        if lastLoadedKey == taskKey, document != nil, errorMessage == nil {
            return
        }
        await loadPDF()
    }

    private func loadPDF() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            // IMPORTANT: don't nil out `document` unless this is a new key
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

        // 2) If deterministic cache exists, use it (even if localPDFPath is nil)
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

        // 3) Download once and write to deterministic cache file
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
                // still set lastLoadedKey so we don't thrash on the same failing URL
                lastLoadedKey = taskKey
            }
        }
    }
}
