import Foundation

/// A field the user fills in, in a small form, before the snippet is inserted.
public struct FillInField: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case text = "fill"
        case multilineText = "fill:multi"
        case choice
        case optional
    }

    public let name: String
    public let kind: Kind
    /// The menu items, for `.choice`. The first one is picked to start with.
    public let options: [String]

    /// Fields with the same name and kind share one value, so they fill in together.
    public var id: String { kind.rawValue + ":" + name }

    public init(name: String, kind: Kind, options: [String] = []) {
        self.name = name
        self.kind = kind
        self.options = options
    }
}

/// What the user entered for each field, keyed by `FillInField.id`.
/// A field with no entry gets its default: empty text, the first choice, or an included section.
public struct FillInValues: Equatable, Sendable {
    /// Text typed or picked, for text and choice fields.
    public var text: [FillInField.ID: String]
    /// Whether each optional section is kept.
    public var included: [FillInField.ID: Bool]

    public init(text: [FillInField.ID: String] = [:], included: [FillInField.ID: Bool] = [:]) {
        self.text = text
        self.included = included
    }
}

/// A stretch of a filled-in snippet.
public enum FillInSegment: Equatable, Sendable {
    /// Snippet text, which may still hold placeholders like `{date}`.
    case template(String)
    /// Something the user entered, to be inserted literally.
    case value(String)
}

/// Snippet content parsed for fill-in fields:
/// `{Name}` or `{fill:Name}` single-line text, `{fill:Name:multi}` multi-line text,
/// `{choice:Name:a|b|c}` popup menu, `{optional:Name}…{/optional}` checkbox section.
/// A bare `{Name}` is only a field when it isn't a built-in placeholder like `{date}` or one of
/// the saved variables; those are filled in automatically by `MacroExpander`.
/// Anything that doesn't parse as a field (unknown tags, an unclosed section) stays as typed.
public struct FillInTemplate: Sendable {
    public static let placeholders = ["{Name}", "{fill:Name:multi}", "{choice:Name:a|b|c}", "{optional:Name}…{/optional}"]

    /// Whether `name` can be written as a bare `{name}`: starts with a letter, then letters,
    /// digits, spaces, `_` or `-`, with no space at either end. Keeps code like `{ return x }`
    /// from turning into a field.
    public static func isBareName(_ name: some StringProtocol) -> Bool {
        guard let first = name.first, first.isLetter, let last = name.last, last != " ", name.count <= 40 else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == " " || $0 == "_" || $0 == "-" }
    }

    /// Each distinct field, in the order it first appears.
    public let fields: [FillInField]
    private let nodes: [Node]

    private indirect enum Node: Sendable {
        case text(String)
        case field(FillInField)
        case optional(FillInField, [Node])
    }

    /// `variableNames` are the saved variables, which a bare `{name}` refers to instead of asking.
    public init(_ content: String, variableNames: Set<String> = []) {
        let reserved = MacroExpander.builtInNames.union(variableNames)
        // Each open {optional} section, innermost last; the bottom one is the snippet itself.
        var stack: [(field: FillInField?, opening: String, nodes: [Node])] = [(nil, "", [])]
        var literal = ""
        func flush() {
            guard !literal.isEmpty else { return }
            stack[stack.count - 1].nodes.append(.text(literal))
            literal = ""
        }

        var rest = content[...]
        while let open = rest.firstIndex(of: "{") {
            literal += rest[..<open]
            rest = rest[open...]
            // `${name}` is a JavaScript or shell template, not a field.
            let afterDollar = open > content.startIndex && content[content.index(before: open)] == "$"
            guard let close = rest.firstIndex(of: "}"),
                  let tag = Tag(rest[rest.index(after: open)..<close], reserved: reserved, afterDollar: afterDollar) else {
                literal += "{"
                rest = rest.dropFirst()
                continue
            }
            let tagText = String(rest[...close])
            rest = rest[rest.index(after: close)...]

            switch tag {
            case .field(let field):
                flush()
                stack[stack.count - 1].nodes.append(.field(field))
            case .optionalStart(let field):
                flush()
                stack.append((field, tagText, []))
            case .optionalEnd:
                guard stack.count > 1, let field = stack[stack.count - 1].field else {
                    literal += tagText
                    continue
                }
                flush()
                let section = stack.removeLast()
                stack[stack.count - 1].nodes.append(.optional(field, section.nodes))
            }
        }
        literal += rest
        flush()

        // Sections that were never closed stay as typed.
        while stack.count > 1 {
            let section = stack.removeLast()
            stack[stack.count - 1].nodes.append(.text(section.opening))
            stack[stack.count - 1].nodes += section.nodes
        }

        nodes = stack[0].nodes
        fields = Self.distinctFields(in: nodes)
    }

    /// What the form starts with: empty text, the first choice, every section included.
    public var defaultValues: FillInValues {
        var values = FillInValues()
        for field in fields {
            switch field.kind {
            case .text, .multilineText, .choice: values.text[field.id] = Self.defaultText(for: field)
            case .optional: values.included[field.id] = true
            }
        }
        return values
    }

    /// The snippet with its fields filled in. Neighbouring template text is merged,
    /// so a placeholder split by a dropped section still reads as one.
    public func render(_ values: FillInValues) -> [FillInSegment] {
        var segments: [FillInSegment] = []
        func emit(_ nodes: [Node]) {
            for node in nodes {
                switch node {
                case .text(let text):
                    if case .template(let previous) = segments.last {
                        segments[segments.count - 1] = .template(previous + text)
                    } else {
                        segments.append(.template(text))
                    }
                case .field(let field):
                    segments.append(.value(values.text[field.id] ?? Self.defaultText(for: field)))
                case .optional(let field, let inner):
                    if values.included[field.id] ?? true { emit(inner) }
                }
            }
        }
        emit(nodes)
        return segments
    }

    private static func defaultText(for field: FillInField) -> String {
        field.kind == .choice ? field.options.first ?? "" : ""
    }

    private static func distinctFields(in nodes: [Node]) -> [FillInField] {
        var fields: [FillInField] = []
        var seen = Set<FillInField.ID>()
        func visit(_ nodes: [Node]) {
            for node in nodes {
                switch node {
                case .text: break
                case .field(let field):
                    if seen.insert(field.id).inserted { fields.append(field) }
                case .optional(let field, let inner):
                    if seen.insert(field.id).inserted { fields.append(field) }
                    visit(inner)
                }
            }
        }
        visit(nodes)
        return fields
    }

    private enum Tag {
        case field(FillInField)
        case optionalStart(FillInField)
        case optionalEnd

        init?(_ body: Substring, reserved: Set<String>, afterDollar: Bool) {
            if body == "/optional" {
                self = .optionalEnd
                return
            }
            guard let colon = body.firstIndex(of: ":") else {
                // A bare {Name}: asked for when inserting, unless it's filled in automatically.
                guard !afterDollar, FillInTemplate.isBareName(body), !reserved.contains(String(body)) else { return nil }
                self = .field(FillInField(name: String(body), kind: .text))
                return
            }
            let rest = body[body.index(after: colon)...]

            let field: FillInField
            switch body[..<colon] {
            case "fill":
                if rest.hasSuffix(":multi") {
                    field = FillInField(name: Self.name(rest.dropLast(":multi".count)), kind: .multilineText)
                } else {
                    field = FillInField(name: Self.name(rest), kind: .text)
                }
            case "choice":
                guard let split = rest.firstIndex(of: ":") else { return nil }
                let options = rest[rest.index(after: split)...].split(separator: "|", omittingEmptySubsequences: false)
                field = FillInField(name: Self.name(rest[..<split]), kind: .choice, options: options.map(String.init))
            case "optional":
                field = FillInField(name: Self.name(rest), kind: .optional)
            default:
                return nil
            }
            guard !field.name.isEmpty else { return nil }
            self = field.kind == .optional ? .optionalStart(field) : .field(field)
        }

        private static func name(_ text: Substring) -> String {
            text.trimmingCharacters(in: .whitespaces)
        }
    }
}
