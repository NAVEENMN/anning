import SwiftUI

struct InlineTextEditor: View {
    let title: String?
    let placeholder: String
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let lineLimit: Int?
    let onCommit: (String) -> Void

    @State private var draft: String
    @State private var isEditing: Bool = false
    @FocusState private var focused: Bool

    init(
        title: String? = nil,
        text: String,
        placeholder: String,
        minHeight: CGFloat = 110,
        maxHeight: CGFloat = 160,
        lineLimit: Int? = 6,
        onCommit: @escaping (String) -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.lineLimit = lineLimit
        self.onCommit = onCommit
        _draft = State(initialValue: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
            }

            if isEditing {
                TextEditor(text: $draft)
                    .focused($focused)
                    .font(.callout)
                    .frame(minHeight: minHeight, maxHeight: maxHeight)
                    .padding(6)
                    .background(EditorStyles.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(EditorStyles.border, lineWidth: 1)
                    )
                    .onChange(of: focused) {
                        if !focused {
                            onCommit(draft)
                            isEditing = false
                        }
                    }
            } else {
                Text(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? placeholder : draft)
                    .font(.callout)
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .primary)
                    .lineLimit(lineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(EditorStyles.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(EditorStyles.subtleBorder, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditing = true
                        focused = true
                    }
            }
        }
    }
}
