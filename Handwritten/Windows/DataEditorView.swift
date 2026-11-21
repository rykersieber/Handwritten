import SwiftUI
import AppKit

/// Edit the word / bigram / misspelling lists.
struct DataEditorView: View {
    let file: WordData.File
    @State private var text: String
    @State private var saved = false

    init(file: WordData.File) {
        self.file = file
        _text = State(initialValue: WordData.read(file))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(file.title).font(.headline)
            Text(file.help).font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            HStack {
                Text("\(text.split(whereSeparator: \.isNewline).count) lines").font(.caption).foregroundStyle(.secondary)
                if saved { Text("Saved ✓").font(.caption).foregroundStyle(.green) }
                Spacer()
                Button("Restore Default") {
                    WordData.shared.restoreDefault(file)
                    text = WordData.read(file)
                }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([WordData.userURL(file)])
                }
                Button("Save") {
                    WordData.write(file, text)
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 420)
    }
}
