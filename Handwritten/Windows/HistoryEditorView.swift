import SwiftUI

struct HistoryEditorView: View {
    let item: ClipboardItem
    @State private var text: String

    init(item: ClipboardItem) {
        self.item = item
        _text = State(initialValue: item.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit before typing").font(.headline)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            HStack {
                Text("\(text.count) characters").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { WindowManager.shared.close(.historyEditor) }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    ClipboardManager.shared.update(item, text: text)
                    WindowManager.shared.close(.historyEditor)
                }
                Button("Save & Use") {
                    ClipboardManager.shared.update(item, text: text)
                    if let updated = ClipboardManager.shared.items.first(where: { $0.id == item.id }) {
                        ClipboardManager.shared.select(updated)
                    }
                    WindowManager.shared.close(.historyEditor)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 320)
    }
}
