/// The last few characters typed, used to spot abbreviations.
public struct TypingBuffer: Sendable {
    public private(set) var text = ""
    public let capacity: Int

    public init(capacity: Int = 64) {
        self.capacity = capacity
    }

    public mutating func append(_ characters: String) {
        text += characters
        if text.count > capacity {
            text = String(text.suffix(capacity))
        }
    }

    public mutating func deleteBackward() {
        if !text.isEmpty { text.removeLast() }
    }

    /// Called when the caret may have moved (click, arrow key, shortcut), so the
    /// buffer no longer matches what is left of the caret.
    public mutating func reset() {
        text = ""
    }
}
