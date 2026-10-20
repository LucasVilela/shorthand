import Foundation

/// Something that was copied, with where and when.
public struct ClipboardEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var text: String
    public var date: Date
    /// The app that was frontmost when it was copied.
    public var sourceBundleID: String?
    public var sourceName: String?

    public init(id: UUID = UUID(), text: String, date: Date = .now, sourceBundleID: String? = nil, sourceName: String? = nil) {
        self.id = id
        self.text = text
        self.date = date
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
    }

    /// The first non-empty line, for lists.
    public var title: String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }
}

/// Recently copied text, newest first, with no duplicates.
public struct ClipboardHistory: Sendable, Equatable {
    public static let defaultLimit = 200
    /// Longer copies (a whole log file, say) aren't kept.
    public static let maxLength = 250_000

    public private(set) var entries: [ClipboardEntry]
    public let limit: Int

    public init(entries: [ClipboardEntry] = [], limit: Int = defaultLimit) {
        self.limit = limit
        self.entries = Array(entries.prefix(limit))
    }

    /// Adds `text` as the newest entry; copying something already in the history moves it
    /// to the top. Blank or very long text is skipped. Returns whether anything changed.
    @discardableResult
    public mutating func record(_ text: String, at date: Date = .now, sourceBundleID: String? = nil, sourceName: String? = nil) -> Bool {
        guard text.utf16.count <= Self.maxLength,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        entries.removeAll { $0.text == text }
        entries.insert(ClipboardEntry(text: text, date: date, sourceBundleID: sourceBundleID, sourceName: sourceName), at: 0)
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        return true
    }

    public mutating func remove(id: ClipboardEntry.ID) {
        entries.removeAll { $0.id == id }
    }

    public mutating func removeAll() {
        entries.removeAll()
    }

    /// Entries containing `query` (ignoring case), newest first; all of them for an empty query.
    public func search(_ query: String) -> [ClipboardEntry] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            $0.text.localizedCaseInsensitiveContains(query) || ($0.sourceName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}
