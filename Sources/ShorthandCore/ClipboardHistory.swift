import Foundation

/// A copied image, saved as a PNG file named by its content hash.
public struct ClipboardImage: Codable, Hashable, Sendable {
    /// SHA-256 of the PNG data, in hex. The same picture copied twice has the same hash.
    public var hash: String
    public var width: Int
    public var height: Int
    public var byteCount: Int

    public init(hash: String, width: Int, height: Int, byteCount: Int) {
        self.hash = hash
        self.width = width
        self.height = height
        self.byteCount = byteCount
    }

    public var fileName: String { "\(hash).png" }
}

/// Something that was copied, with where and when: text, or an image.
public struct ClipboardEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// The copied text; empty for an image.
    public var text: String
    /// Set when an image was copied. Entries saved before images were supported don't have it.
    public var image: ClipboardImage?
    public var date: Date
    /// The app that was frontmost when it was copied.
    public var sourceBundleID: String?
    public var sourceName: String?

    public init(
        id: UUID = UUID(),
        text: String = "",
        image: ClipboardImage? = nil,
        date: Date = .now,
        sourceBundleID: String? = nil,
        sourceName: String? = nil
    ) {
        self.id = id
        self.text = text
        self.image = image
        self.date = date
        self.sourceBundleID = sourceBundleID
        self.sourceName = sourceName
    }

    /// The first non-empty line, or "Image · 1920×1080", for lists.
    public var title: String {
        if let image { return "Image · \(image.width)×\(image.height)" }
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }
}

/// Recently copied text and images, newest first, with no duplicates.
public struct ClipboardHistory: Sendable, Equatable {
    public static let defaultLimit = 200
    /// Images take far more space than text, so fewer are kept.
    public static let defaultImageLimit = 50
    /// Longer copies (a whole log file, say) aren't kept.
    public static let maxLength = 250_000

    public private(set) var entries: [ClipboardEntry]
    public let limit: Int
    public let imageLimit: Int

    public init(entries: [ClipboardEntry] = [], limit: Int = defaultLimit, imageLimit: Int = defaultImageLimit) {
        self.limit = limit
        self.imageLimit = imageLimit
        self.entries = entries
        trim()
    }

    /// Image files the history still uses. Any other file in the image folder can go.
    public var imageFileNames: Set<String> {
        Set(entries.compactMap { $0.image?.fileName })
    }

    /// Adds `text` as the newest entry; copying something already in the history moves it
    /// to the top. Blank or very long text is skipped. Returns whether anything changed.
    @discardableResult
    public mutating func record(_ text: String, at date: Date = .now, sourceBundleID: String? = nil, sourceName: String? = nil) -> Bool {
        guard text.utf16.count <= Self.maxLength,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        entries.removeAll { $0.image == nil && $0.text == text }
        add(ClipboardEntry(text: text, date: date, sourceBundleID: sourceBundleID, sourceName: sourceName))
        return true
    }

    /// Adds an image as the newest entry; the same image copied again moves to the top.
    public mutating func record(_ image: ClipboardImage, at date: Date = .now, sourceBundleID: String? = nil, sourceName: String? = nil) {
        entries.removeAll { $0.image?.hash == image.hash }
        add(ClipboardEntry(image: image, date: date, sourceBundleID: sourceBundleID, sourceName: sourceName))
    }

    public mutating func remove(id: ClipboardEntry.ID) {
        entries.removeAll { $0.id == id }
    }

    public mutating func removeAll() {
        entries.removeAll()
    }

    /// Entries whose text, title or source app contains `query` (ignoring case), newest
    /// first; all of them for an empty query. "image" finds the images.
    public func search(_ query: String) -> [ClipboardEntry] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter {
            ($0.image == nil ? $0.text : $0.title).localizedCaseInsensitiveContains(query)
                || ($0.sourceName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private mutating func add(_ entry: ClipboardEntry) {
        entries.insert(entry, at: 0)
        trim()
    }

    /// Drops the oldest entries past `limit`, and the oldest images past `imageLimit`.
    private mutating func trim() {
        if entries.count > limit {
            entries.removeLast(entries.count - limit)
        }
        var imagesKept = 0
        entries.removeAll { entry in
            guard entry.image != nil else { return false }
            imagesKept += 1
            return imagesKept > imageLimit
        }
    }
}
