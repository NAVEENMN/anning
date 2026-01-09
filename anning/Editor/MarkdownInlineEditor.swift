import SwiftUI
import AppKit

enum MarkdownCommand: Equatable {
    case bold
    case italic
    case underline
    case bulletList
    case numberedList
    case link
    case codeBlock
}

/// Click-to-edit editor with toolbar. Saves when you click outside the editor.
struct InlineMarkdownEditor: View {
    let title: String?
    let placeholder: String
    @Binding var text: String
    let onCommit: () -> Void

    @State private var isEditing = false

    init(
        title: String? = nil,
        text: Binding<String>,
        placeholder: String,
        onCommit: @escaping () -> Void
    ) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
            }

            if isEditing {
                MarkdownEditorNSView(text: $text, isEditing: $isEditing) {
                    onCommit()
                }
                .frame(minHeight: 150, maxHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
            } else {
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : text)
                    .font(.callout)
                    .foregroundStyle(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.black.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { isEditing = true }
            }
        }
    }
}

// MARK: - NSViewRepresentable (toolbar + NSTextView)

private struct MarkdownEditorNSView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    let onCommit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)

        // Toolbar hosting view
        let toolbarHost = NSHostingView(rootView: MarkdownToolbar { cmd in
            context.coordinator.apply(cmd)
        })
        toolbarHost.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbarHost)

        // Scroll view + text view
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)

        let tv = NSTextView()
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.font = NSFont.systemFont(ofSize: 13)
        tv.string = text
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 8, height: 8)

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

        context.coordinator.container = container
        context.coordinator.textView = tv
        context.coordinator.scrollView = scroll
        context.coordinator.setBindings(text: $text, isEditing: $isEditing, onCommit: onCommit)

        tv.delegate = context.coordinator
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.setBindings(text: $text, isEditing: $isEditing, onCommit: onCommit)

        // If SwiftUI toggled editing off, stop monitoring.
        if !isEditing {
            context.coordinator.stopOutsideClickMonitor()
        } else {
            context.coordinator.startOutsideClickMonitorIfNeeded()
        }

        // Keep NSTextView in sync when external text changes (only if not actively editing selection)
        if let tv = context.coordinator.textView, tv.string != text {
            tv.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var container: NSView?
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?

        private var textBinding: Binding<String>?
        private var editingBinding: Binding<Bool>?
        private var onCommit: (() -> Void)?

        private var outsideMonitor: Any?

        func setBindings(text: Binding<String>, isEditing: Binding<Bool>, onCommit: @escaping () -> Void) {
            self.textBinding = text
            self.editingBinding = isEditing
            self.onCommit = onCommit
        }

        // MARK: NSTextViewDelegate
        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            textBinding?.wrappedValue = tv.string
        }

        // MARK: Outside click = save + exit
        func startOutsideClickMonitorIfNeeded() {
            guard outsideMonitor == nil else { return }
            outsideMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
                guard let self else { return event }
                guard let container = self.container, let window = container.window else { return event }

                let p = container.convert(event.locationInWindow, from: nil)
                let inside = container.bounds.contains(p)

                if !inside {
                    self.commitAndClose()
                } else {
                    // if click is inside toolbar, keep focus behavior predictable
                    if let tv = self.textView {
                        DispatchQueue.main.async { window.makeFirstResponder(tv) }
                    }
                }
                return event
            }
        }

        func stopOutsideClickMonitor() {
            if let outsideMonitor {
                NSEvent.removeMonitor(outsideMonitor)
                self.outsideMonitor = nil
            }
        }

        private func commitAndClose() {
            stopOutsideClickMonitor()
            onCommit?()
            editingBinding?.wrappedValue = false
        }

        // MARK: Commands
        func apply(_ cmd: MarkdownCommand) {
            guard let tv = textView else { return }
            tv.window?.makeFirstResponder(tv)

            switch cmd {
            case .bold: wrapSelection(in: tv, prefix: "**", suffix: "**")
            case .italic: wrapSelection(in: tv, prefix: "*", suffix: "*")
            case .underline: wrapSelection(in: tv, prefix: "<u>", suffix: "</u>")
            case .codeBlock: wrapSelection(in: tv, prefix: "```\n", suffix: "\n```")
            case .bulletList: listify(in: tv, numbered: false)
            case .numberedList: listify(in: tv, numbered: true)
            case .link: insertLink(in: tv)
            }

            textBinding?.wrappedValue = tv.string
        }

        private func wrapSelection(in tv: NSTextView, prefix: String, suffix: String) {
            let ns = tv.string as NSString
            let range = tv.selectedRange()

            if range.length == 0 {
                let insert = prefix + suffix
                tv.insertText(insert, replacementRange: range)
                let newLoc = range.location + (prefix as NSString).length
                tv.setSelectedRange(NSRange(location: newLoc, length: 0))
                return
            }

            let selected = ns.substring(with: range)
            let replaced = prefix + selected + suffix
            tv.insertText(replaced, replacementRange: range)
            tv.setSelectedRange(NSRange(location: range.location + (prefix as NSString).length, length: (selected as NSString).length))
        }

        private func listify(in tv: NSTextView, numbered: Bool) {
            let ns = tv.string as NSString
            var range = tv.selectedRange()

            // If nothing selected, operate on current line
            if range.length == 0 {
                range = ns.lineRange(for: range)
            } else {
                // Expand to full line range covering selection
                let startLine = ns.lineRange(for: NSRange(location: range.location, length: 0))
                let endLoc = range.location + range.length
                let endLine = ns.lineRange(for: NSRange(location: max(0, endLoc - 1), length: 0))
                let unionStart = startLine.location
                let unionEnd = endLine.location + endLine.length
                range = NSRange(location: unionStart, length: unionEnd - unionStart)
            }

            let block = ns.substring(with: range)
            var lines = block.components(separatedBy: "\n")

            // Preserve trailing empty line caused by lineRange
            let hadTrailingEmpty = lines.last == ""
            if hadTrailingEmpty { lines.removeLast() }

            var out: [String] = []
            var n = 1
            for line in lines {
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    out.append(line)
                    continue
                }
                if numbered {
                    out.append("\(n). \(line)")
                    n += 1
                } else {
                    out.append("- \(line)")
                }
            }

            var replaced = out.joined(separator: "\n")
            if hadTrailingEmpty { replaced += "\n" }

            tv.insertText(replaced, replacementRange: range)
            tv.setSelectedRange(NSRange(location: range.location, length: (replaced as NSString).length))
        }

        private func insertLink(in tv: NSTextView) {
            let ns = tv.string as NSString
            let range = tv.selectedRange()
            let selectedText = range.length > 0 ? ns.substring(with: range) : "link text"

            let url = promptForURL() ?? ""
            if url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

            let replaced = "[\(selectedText)](\(url))"
            tv.insertText(replaced, replacementRange: range)

            // Put cursor at end
            tv.setSelectedRange(NSRange(location: range.location + (replaced as NSString).length, length: 0))
        }

        private func promptForURL() -> String? {
            let field = NSTextField(string: "")
            field.placeholderString = "https://..."

            let alert = NSAlert()
            alert.messageText = "Insert Link"
            alert.informativeText = "Enter a URL"
            alert.accessoryView = field
            alert.addButton(withTitle: "Insert")
            alert.addButton(withTitle: "Cancel")

            let res = alert.runModal()
            if res != .alertFirstButtonReturn { return nil }

            return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

// MARK: - Toolbar

private struct MarkdownToolbar: View {
    let onCommand: (MarkdownCommand) -> Void

    var body: some View {
        HStack(spacing: 10) {
            toolbarButton("B") { onCommand(.bold) }
            toolbarButton("I") { onCommand(.italic) }
            toolbarButton("U") { onCommand(.underline) }

            Divider().frame(height: 18)

            toolbarIcon("link") { onCommand(.link) }
            toolbarIcon("list.number") { onCommand(.numberedList) }
            toolbarIcon("list.bullet") { onCommand(.bulletList) }

            Divider().frame(height: 18)

            toolbarIcon("chevron.left.slash.chevron.right") { onCommand(.codeBlock) }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.06))
    }

    private func toolbarButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
    }

    private func toolbarIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
    }
}

