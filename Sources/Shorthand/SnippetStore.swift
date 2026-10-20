import Foundation
import Observation
import ShorthandCore

/// Snippets and variables, saved as JSON in ~/Library/Application Support/Shorthand/
/// (snippets.json and variables.json). Every change is written straight away.
@MainActor
@Observable
final class SnippetStore {
    var snippets: [Snippet] = [] {
        didSet {
            guard isLoaded else { return }
            save(snippets, to: snippetsURL)
            onChange?(snippets)
        }
    }

    /// Values filled in automatically wherever a snippet says `{name}`.
    var variables: [Variable] = [] {
        didSet {
            guard isLoaded else { return }
            save(variables, to: variablesURL)
            onVariablesChange?(variables)
        }
    }

    @ObservationIgnored var onChange: (([Snippet]) -> Void)?
    @ObservationIgnored var onVariablesChange: (([Variable]) -> Void)?
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private let snippetsURL: URL
    @ObservationIgnored private let variablesURL: URL

    init(directory: URL = SnippetStore.defaultDirectory) {
        snippetsURL = directory.appending(path: "snippets.json")
        variablesURL = directory.appending(path: "variables.json")
        snippets = load(from: snippetsURL, fallback: Snippet.samples)
        variables = load(from: variablesURL, fallback: Variable.samples)
        isLoaded = true
        if !FileManager.default.fileExists(atPath: snippetsURL.path) { save(snippets, to: snippetsURL) }
        if !FileManager.default.fileExists(atPath: variablesURL.path) { save(variables, to: variablesURL) }
    }

    /// ~/Library/Application Support/Shorthand, or SHORTHAND_DATA_DIR when set, so a
    /// development build can run against test data instead of yours.
    static var defaultDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["SHORTHAND_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL.applicationSupportDirectory.appending(path: "Shorthand", directoryHint: .isDirectory)
    }

    /// Saved variables by name, ready for `MacroExpander`.
    var variableValues: [String: String] {
        Variable.lookup(variables)
    }

    @discardableResult
    func add(abbreviation: String) -> Snippet {
        let snippet = Snippet(abbreviation: abbreviation, content: "")
        snippets.append(snippet)
        return snippet
    }

    func delete(id: Snippet.ID) {
        snippets.removeAll { $0.id == id }
    }

    /// Abbreviations used by more than one enabled snippet.
    var duplicateAbbreviations: Set<String> {
        var seen = Set<String>(), duplicates = Set<String>()
        for snippet in snippets where snippet.isEnabled && !snippet.abbreviation.isEmpty {
            if !seen.insert(snippet.abbreviation).inserted { duplicates.insert(snippet.abbreviation) }
        }
        return duplicates
    }

    private func load<Value: Decodable>(from url: URL, fallback: Value) -> Value {
        guard let data = try? Data(contentsOf: url) else { return fallback }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            // Keep the unreadable file instead of overwriting it.
            let backup = url.deletingPathExtension()
                .appendingPathExtension("unreadable-\(Int(Date.now.timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            NSLog("Shorthand: couldn't read \(url.path) (\(error)); moved it to \(backup.lastPathComponent)")
            return fallback
        }
    }

    private func save<Value: Encodable>(_ value: Value, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            NSLog("Shorthand: couldn't save \(url.lastPathComponent): \(error)")
        }
    }
}
