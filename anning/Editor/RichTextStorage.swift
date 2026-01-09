import Foundation
import AppKit

enum RichTextStorage {
    static let prefix = "rtfbase64:"

    static func encodeRTFBase64(_ attributed: NSAttributedString) -> String {
        do {
            let data = try attributed.data(
                from: NSRange(location: 0, length: attributed.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            return prefix + data.base64EncodedString()
        } catch {
            // fallback: store plain text
            return attributed.string
        }
    }

    static func decodeToNSAttributedString(_ stored: String) -> NSAttributedString {
        let s = stored

        if s.hasPrefix(prefix) {
            let b64 = String(s.dropFirst(prefix.count))
            if let data = Data(base64Encoded: b64) {
                if let attr = try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                ) {
                    return attr
                }
            }
            return NSAttributedString(string: "")
        }

        // If it's old markdown-ish content, try to render it nicely.
        if let a = try? AttributedString(markdown: s) {
            return NSAttributedString(a)
        }

        return NSAttributedString(string: s)
    }

    static func plainText(_ stored: String?) -> String {
        guard let stored else { return "" }
        return decodeToNSAttributedString(stored).string
    }

    static func isEffectivelyEmpty(_ stored: String?) -> Bool {
        plainText(stored).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

