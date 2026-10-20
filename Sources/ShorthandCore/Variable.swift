import Foundation

/// A saved value you write as `{name}` in any snippet, e.g. `{company}` → "Acme Pty Ltd".
/// Filled in automatically, unlike a fill-in field, which asks each time.
public struct Variable: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var value: String

    public init(id: UUID = UUID(), name: String, value: String) {
        self.id = id
        self.name = name
        self.value = value
    }

    /// Why `name` won't work as `{name}`, or nil when it's fine.
    public var nameProblem: String? {
        if name.isEmpty { return "Give it a name" }
        if MacroExpander.builtInNames.contains(name) { return "{\(name)} is already a built-in placeholder" }
        if !FillInTemplate.isBareName(name) { return "Use letters, digits, spaces, _ or -, starting with a letter" }
        return nil
    }

    public static let samples: [Variable] = [
        Variable(name: "my name", value: "Lucas"),
        Variable(name: "company", value: "Your Company (edit in Variables)"),
    ]

    /// Usable variables by name. If two share a name, the first wins.
    public static func lookup(_ variables: [Variable]) -> [String: String] {
        var values: [String: String] = [:]
        for variable in variables where variable.nameProblem == nil && values[variable.name] == nil {
            values[variable.name] = variable.value
        }
        return values
    }
}
