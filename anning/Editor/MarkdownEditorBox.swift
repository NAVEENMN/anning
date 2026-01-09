import SwiftUI
import AppKit

struct MarkdownEditorBox: View {
    @Binding var text: String
    var placeholder: String = ""
    var minHeight: CGFloat = 160
    var maxHeight: CGFloat = 280

    var body: some View {
        RichTextEditorNSView(storedText: $text, placeholder: placeholder)
            .frame(minHeight: minHeight, maxHeight: maxHeight)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
    }
}

// MARK: - Rich NSTextView + toolbar

private struct RichTextEditorNSView: NSViewRepresentable {
    @Binding var storedText: String
    let placeholder: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)

        let toolbarHost = NSHostingView(rootView: ToolbarView { cmd in
            context.coordinator.apply(cmd)
        })
        toolbarHost.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbarHost)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)

        let tv = NSTextView()
        tv.isRichText = true
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.delegate = context.coordinator

        // Load rich content
        tv.textStorage?.setAttributedString(RichTextStorage.decodeToNSAttributedString(storedText))

        scroll.documentView = tv

        NSLayoutConstraint.activate([
            toolbarHost.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbarHost.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbarHost.topAnchor.constraint(equalTo: container.topAnchor),
            toolbarHost.heightAnchor.constraint(equalToConstant: 40),

            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: toolbarHost.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Placeholder label
        let placeholderField = NSTextField(labelWithString: placeholder)
        placeholderField.textColor = .secondaryLabelColor
        placeholderField.font = NSFont.systemFont(ofSize: 13)
        placeholderField.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(placeholderField)
        NSLayoutConstraint.activate([
            placeholderField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            placeholderField.topAnchor.constraint(equalTo: toolbarHost.bottomAnchor, constant: 12),
            placeholderField.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -14),
        ])

        context.coordinator.textView = tv
        context.coordinator.placeholderLabel = placeholderField
        context.coordinator.bindStoredText($storedText)
        context.coordinator.refreshPlaceholder()

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.bindStoredText($storedText)

        // If external storage changed (open project / new project), reload into text view
        if let tv = context.coordinator.textView {
            let currentEncoded = RichTextStorage.encodeRTFBase64(tv.attributedString())
            if currentEncoded != storedText {
                tv.textStorage?.setAttributedString(RichTextStorage.decodeToNSAttributedString(storedText))
            }
        }

        context.coordinator.refreshPlaceholder()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        weak var placeholderLabel: NSTextField?
        private var storedBinding: Binding<String>?

        func bindStoredText(_ b: Binding<String>) { storedBinding = b }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            let encoded = RichTextStorage.encodeRTFBase64(tv.attributedString())
            storedBinding?.wrappedValue = encoded
            refreshPlaceholder()
        }

        func refreshPlaceholder() {
            let empty = RichTextStorage.isEffectivelyEmpty(storedBinding?.wrappedValue)
            placeholderLabel?.isHidden = !empty
        }

        func apply(_ cmd: RichCmd) {
            guard let tv = textView else { return }
            tv.window?.makeFirstResponder(tv)

            switch cmd {
            case .bold: toggleFontTrait(.boldFontMask, tv)
            case .italic: toggleFontTrait(.italicFontMask, tv)
            case .underline: toggleUnderline(tv)
            case .bullet: applyList(tv, numbered: false)
            case .numbered: applyList(tv, numbered: true)
            case .link: applyLink(tv)
            case .code: applyCodeBlock(tv)
            }

            // Update storage after command
            let encoded = RichTextStorage.encodeRTFBase64(tv.attributedString())
            storedBinding?.wrappedValue = encoded
            refreshPlaceholder()
        }

        // MARK: Formatting helpers

        private func toggleFontTrait(_ trait: NSFontTraitMask, _ tv: NSTextView) {
            let range = tv.selectedRange()
            let fm = NSFontManager.shared

            if range.length == 0 {
                let font = (tv.typingAttributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 13)
                let has = fm.traits(of: font).contains(trait)
                let newFont = has ? fm.convert(font, toNotHaveTrait: trait) : fm.convert(font, toHaveTrait: trait)
                tv.typingAttributes[.font] = newFont
                return
            }

            guard let storage = tv.textStorage else { return }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range, options: []) { value, subRange, _ in
                let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: 13)
                let has = fm.traits(of: font).contains(trait)
                let newFont = has ? fm.convert(font, toNotHaveTrait: trait) : fm.convert(font, toHaveTrait: trait)
                storage.addAttribute(.font, value: newFont, range: subRange)
            }
            storage.endEditing()
        }

        private func toggleUnderline(_ tv: NSTextView) {
            let range = tv.selectedRange()
            guard let storage = tv.textStorage else { return }

            let probeLoc = max(0, min(range.location, storage.length - 1))
            let existing = storage.attribute(.underlineStyle, at: probeLoc, effectiveRange: nil) as? Int
            let shouldRemove = (existing ?? 0) != 0

            let applyRange = (range.length == 0 && storage.length > 0) ? NSRange(location: probeLoc, length: 0) : range

            if applyRange.length == 0 {
                // toggle typing attributes
                tv.typingAttributes[.underlineStyle] = shouldRemove ? nil : NSUnderlineStyle.single.rawValue
                return
            }

            storage.beginEditing()
            if shouldRemove {
                storage.removeAttribute(.underlineStyle, range: applyRange)
            } else {
                storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: applyRange)
            }
            storage.endEditing()
        }

        private func applyList(_ tv: NSTextView, numbered: Bool) {
            guard let storage = tv.textStorage else { return }
            let ns = storage.string as NSString
            var range = tv.selectedRange()

            if range.length == 0 {
                range = ns.lineRange(for: range)
            } else {
                let start = ns.lineRange(for: NSRange(location: range.location, length: 0))
                let endLoc = range.location + range.length
                let end = ns.lineRange(for: NSRange(location: max(0, endLoc - 1), length: 0))
                range = NSRange(location: start.location, length: (end.location + end.length) - start.location)
            }

            let list = NSTextList(markerFormat: numbered ? .decimal : .disc, options: 0)
            let ps = NSMutableParagraphStyle()
            ps.textLists = [list]
            ps.headIndent = 18
            ps.firstLineHeadIndent = 0
            ps.paragraphSpacing = 2

            storage.beginEditing()
            storage.addAttribute(.paragraphStyle, value: ps, range: range)
            storage.endEditing()
        }

        private func applyLink(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let range = tv.selectedRange()
            if range.length == 0 { return }

            let field = NSTextField(string: "")
            field.placeholderString = "https://..."

            let alert = NSAlert()
            alert.messageText = "Insert Link"
            alert.informativeText = "Enter a URL"
            alert.accessoryView = field
            alert.addButton(withTitle: "Insert")
            alert.addButton(withTitle: "Cancel")

            if alert.runModal() != .alertFirstButtonReturn { return }
            let urlString = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: urlString), !urlString.isEmpty else { return }

            storage.beginEditing()
            storage.addAttribute(.link, value: url, range: range)
            storage.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: range)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            storage.endEditing()
        }

        private func applyCodeBlock(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let ns = storage.string as NSString
            var range = tv.selectedRange()

            if range.length == 0 {
                range = ns.lineRange(for: range)
            } else {
                let start = ns.lineRange(for: NSRange(location: range.location, length: 0))
                let endLoc = range.location + range.length
                let end = ns.lineRange(for: NSRange(location: max(0, endLoc - 1), length: 0))
                range = NSRange(location: start.location, length: (end.location + end.length) - start.location)
            }

            let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let bg = NSColor.textBackgroundColor.withAlphaComponent(0.18)

            let ps = NSMutableParagraphStyle()
            ps.paragraphSpacing = 6
            ps.headIndent = 0
            ps.firstLineHeadIndent = 0

            storage.beginEditing()
            storage.addAttribute(.font, value: font, range: range)
            storage.addAttribute(.backgroundColor, value: bg, range: range)
            storage.addAttribute(.paragraphStyle, value: ps, range: range)
            storage.endEditing()
        }
    }
}

private enum RichCmd: Equatable { case bold, italic, underline, numbered, bullet, link, code }

private struct ToolbarView: View {
    let onCommand: (RichCmd) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("B") { onCommand(.bold) }.buttonStyle(.borderless)
            Button("I") { onCommand(.italic) }.buttonStyle(.borderless)
            Button("U") { onCommand(.underline) }.buttonStyle(.borderless)

            Divider().frame(height: 18)

            Button { onCommand(.link) } label: { Image(systemName: "link") }
                .buttonStyle(.borderless)
            Button { onCommand(.numbered) } label: { Image(systemName: "list.number") }
                .buttonStyle(.borderless)
            Button { onCommand(.bullet) } label: { Image(systemName: "list.bullet") }
                .buttonStyle(.borderless)

            Divider().frame(height: 18)

            Button { onCommand(.code) } label: { Image(systemName: "chevron.left.slash.chevron.right") }
                .buttonStyle(.borderless)

            Spacer()
        }
        .font(.system(size: 13, weight: .semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.06))
    }
}
