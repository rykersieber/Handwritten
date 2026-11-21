import Foundation

struct ClipboardItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date = Date()
    var pinned = false
    var sourceApp: String?

    var preview: String {
        text.replacingOccurrences(of: "\n", with: " ⏎ ").replacingOccurrences(of: "\t", with: " ")
    }

    func preview(_ length: Int) -> String {
        let p = preview
        return p.count > length ? String(p.prefix(length)) + "…" : p
    }

    var wordCount: Int { text.split { $0.isWhitespace }.count }
}
