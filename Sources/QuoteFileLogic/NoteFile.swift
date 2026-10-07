import Foundation

public enum NoteFile {
    public static func resolvedPath() -> String {
        if let env = ProcessInfo.processInfo.environment["QUOTE_FILE"], !env.isEmpty {
            return NSString(string: env).expandingTildeInPath
        }
        return NSString(string: "~/notes/quote.md").expandingTildeInPath
    }

    public static func format(quote: String?, note: String) -> String {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let quoteText = quote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasQuote = !quoteText.isEmpty
        let hasNote = !trimmedNote.isEmpty

        if !hasQuote && !hasNote {
            return ""
        }

        var parts: [String] = []
        if hasQuote {
            let block = quoteText.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line in
                    if line.isEmpty { return ">" }
                    return "> \(line)"
                }
                .joined(separator: "\n")
            parts.append(block)
        }
        if hasNote {
            if hasQuote {
                parts.append("")
            }
            parts.append(trimmedNote)
        }
        parts.append("")
        parts.append("---")
        parts.append("")
        return parts.joined(separator: "\n")
    }

    public static func append(entry: String, toExisting existing: String) -> String {
        guard !entry.isEmpty else { return existing }
        if existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return entry
        }
        var result = existing
        if !result.hasSuffix("\n") {
            result += "\n"
        }
        return result + entry
    }

    public static func readContents(at path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: path) {
            return try String(contentsOf: url, encoding: .utf8)
        }
        return ""
    }

    public static func writeContents(_ text: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func appendNote(quote: String?, note: String, path: String) throws {
        let existing = try readContents(at: path)
        let entry = format(quote: quote, note: note)
        guard !entry.isEmpty else { return }
        let merged = append(entry: entry, toExisting: existing)
        try writeContents(merged, to: path)
    }

    public static func sendNotes(path: String) throws -> String {
        let contents = try readContents(at: path)
        guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        let backup = dir.appendingPathComponent("quote.last.md").path
        if FileManager.default.fileExists(atPath: path) {
            if FileManager.default.fileExists(atPath: backup) {
                try FileManager.default.removeItem(atPath: backup)
            }
            try FileManager.default.copyItem(atPath: path, toPath: backup)
        }
        try writeContents("", to: path)
        return contents
    }
}
