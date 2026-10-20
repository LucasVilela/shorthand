import Foundation

public struct ExpansionResult: Equatable, Sendable {
    public var text: String
    /// How many characters the caret should move left after inserting `text`,
    /// so it lands where `{cursor}` was. 0 when there is no `{cursor}`.
    public var cursorOffsetFromEnd: Int
}

/// Fills in snippet placeholders that need no input:
/// `{date}` medium date, `{time}` short time, `{isodate}` YYYY-MM-DD,
/// `{clipboard}` current clipboard text, `{cursor}` where the caret ends up,
/// and `{name}` for each saved variable.
public struct MacroExpander: Sendable {
    public static let placeholders = ["{date}", "{time}", "{isodate}", "{clipboard}", "{cursor}"]
    /// Names a variable can't take, because the placeholder above already means something.
    public static let builtInNames: Set<String> = ["date", "time", "isodate", "clipboard", "cursor"]

    public var now: Date
    public var clipboard: String
    /// Saved variables, by name.
    public var variables: [String: String]
    public var locale: Locale
    public var timeZone: TimeZone

    public init(
        now: Date = .now,
        clipboard: String = "",
        variables: [String: String] = [:],
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        self.now = now
        self.clipboard = clipboard
        self.variables = variables
        self.locale = locale
        self.timeZone = timeZone
    }

    /// Expands `template`, giving any fill-in fields their default values.
    public func expand(_ template: String) -> ExpansionResult {
        expand(FillInTemplate(template, variableNames: Set(variables.keys)), values: FillInValues())
    }

    /// Expands a snippet with its fill-in fields set to `values`. What the user
    /// entered is inserted literally, like the clipboard.
    public func expand(_ template: FillInTemplate, values: FillInValues) -> ExpansionResult {
        var before = ""
        var after = ""
        var foundCursor = false
        for segment in template.render(values) {
            switch segment {
            case .value(let value):
                if foundCursor { after += value } else { before += value }
            case .template(let text):
                // Split on the first {cursor} before substituting, so a {cursor} that
                // arrives inside the clipboard text is inserted literally.
                var parts = text.components(separatedBy: "{cursor}")
                if !foundCursor && parts.count > 1 {
                    before += fill(parts.removeFirst())
                    foundCursor = true
                }
                if foundCursor { after += fill(parts.joined()) } else { before += fill(parts.joined()) }
            }
        }
        return ExpansionResult(text: before + after, cursorOffsetFromEnd: after.count)
    }

    /// One pass over the text, so a substituted value (the clipboard, a variable)
    /// is inserted literally even if it contains something like `{date}`.
    private func fill(_ text: String) -> String {
        guard text.contains("{") else { return text }
        var result = ""
        var rest = text[...]
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let afterOpen = rest.index(after: open)
            if let close = rest[afterOpen...].firstIndex(of: "}"), let value = value(for: rest[afterOpen..<close]) {
                result += value
                rest = rest[rest.index(after: close)...]
            } else {
                result += "{"
                rest = rest[afterOpen...]
            }
        }
        return result + rest
    }

    private func value(for name: Substring) -> String? {
        switch name {
        case "date": format(date: .medium, time: .none)
        case "time": format(date: .none, time: .short)
        case "isodate": isoDate()
        case "clipboard": clipboard
        default: variables[String(name)]
        }
    }

    private func format(date: DateFormatter.Style, time: DateFormatter.Style) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = date
        formatter.timeStyle = time
        return formatter.string(from: now)
    }

    private func isoDate() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
