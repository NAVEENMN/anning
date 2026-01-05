import SwiftUI
import PDFKit

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

