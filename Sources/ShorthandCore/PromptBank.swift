import Foundation

/// The Prompt Bank: text you reuse often but don't want a shortcut for.
/// A snippet with no abbreviation lives only here; typing `trigger` anywhere
/// opens a searchable picker over the bank (and, after it, all shortcut snippets).
public enum PromptBank {
    public static let trigger = ";;"

    /// Enabled snippets with no abbreviation, in the order they were saved.
    public static func entries(in snippets: [Snippet]) -> [Snippet] {
        snippets.filter { $0.isEnabled && $0.abbreviation.isEmpty && !$0.content.isEmpty }
    }

    /// The name shown in lists: the label, else the first non-empty line of the content.
    public static func title(of snippet: Snippet) -> String {
        if !snippet.label.isEmpty { return snippet.label }
        let firstLine = snippet.content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return firstLine ?? snippet.abbreviation
    }

    /// Enabled snippets matching `query`, best first: titles starting with the query,
    /// then titles or abbreviations containing it, then content containing it.
    /// Within each rank, Prompt Bank entries come before shortcut snippets.
    public static func search(_ snippets: [Snippet], for query: String) -> [Snippet] {
        let query = query.trimmingCharacters(in: .whitespaces)
        let ranked: [(rank: Int, isShortcut: Bool, index: Int, snippet: Snippet)] =
            snippets.enumerated().compactMap { index, snippet in
                guard snippet.isEnabled, !snippet.content.isEmpty else { return nil }
                let title = title(of: snippet)
                let rank: Int
                if query.isEmpty || title.lowercased().hasPrefix(query.lowercased()) {
                    rank = 0
                } else if title.localizedCaseInsensitiveContains(query) || snippet.abbreviation.localizedCaseInsensitiveContains(query) {
                    rank = 1
                } else if snippet.content.localizedCaseInsensitiveContains(query) {
                    rank = 2
                } else {
                    return nil
                }
                return (rank, !snippet.abbreviation.isEmpty, index, snippet)
            }
        return ranked
            .sorted { ($0.rank, $0.isShortcut ? 1 : 0, $0.index) < ($1.rank, $1.isShortcut ? 1 : 0, $1.index) }
            .map(\.snippet)
    }
}
