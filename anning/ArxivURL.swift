import Foundation

/// Normalizes common arXiv links into a direct PDF URL.
/// - abs -> pdf + ".pdf"
/// - pdf without ".pdf" -> adds ".pdf"
func normalizeArxivPDFURL(_ raw: String) -> String {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return s }

    // Convert abs to pdf
    if s.contains("arxiv.org/abs/") {
        var out = s.replacingOccurrences(of: "arxiv.org/abs/", with: "arxiv.org/pdf/")
        if !out.lowercased().hasSuffix(".pdf") { out += ".pdf" }
        return out
    }

    // If already pdf but missing suffix
    if s.contains("arxiv.org/pdf/") && !s.lowercased().hasSuffix(".pdf") {
        return s + ".pdf"
    }

    return s
}

/// arXiv-only validation: must be https, host arxiv.org, path contains /pdf/ and ends with .pdf
func isValidArxivPDFURL(_ s: String) -> Bool {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed) else { return false }
    guard url.scheme?.lowercased() == "https" else { return false }
    guard url.host?.lowercased() == "arxiv.org" else { return false }

    let path = url.path.lowercased() // e.g. /pdf/1706.03762.pdf
    guard path.contains("/pdf/") else { return false }
    guard path.hasSuffix(".pdf") else { return false }

    return true
}

