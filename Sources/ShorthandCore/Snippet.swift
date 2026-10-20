import Foundation

/// A saved piece of text that replaces its abbreviation when typed.
public struct Snippet: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    /// What you type, e.g. ";sig". Matched exactly, case-sensitive.
    public var abbreviation: String
    /// What gets inserted. May contain placeholders, see `MacroExpander`.
    public var content: String
    /// Optional description shown in the editor list.
    public var label: String
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        abbreviation: String,
        content: String,
        label: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.abbreviation = abbreviation
        self.content = content
        self.label = label
        self.isEnabled = isEnabled
    }

    // Tolerates hand-edited JSON that leaves out the optional fields.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        abbreviation = try container.decode(String.self, forKey: .abbreviation)
        content = try container.decode(String.self, forKey: .content)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? ""
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }

    public static let samples: [Snippet] = [
        Snippet(abbreviation: ";sig", content: "Cheers,\nLucas", label: "Email sign-off"),
        Snippet(abbreviation: ";date", content: "{date}", label: "Today's date"),
        Snippet(abbreviation: ";iso", content: "{isodate}", label: "Today as YYYY-MM-DD"),
        Snippet(abbreviation: ";ty", content: "Thanks so much, {cursor}! Really appreciate it.", label: "Thank-you with cursor"),
        Snippet(abbreviation: ";shrug", content: "¯\\_(ツ)_/¯", label: "Shrug"),
        // Templates: {Client Name}, {Day} and {project} are asked for; {my name} and {company} are variables.
        Snippet(
            abbreviation: ";meet",
            content: "Hi {Client Name},\n\nAre you free for a quick call on {choice:Day:Monday|Tuesday|Wednesday|Thursday|Friday} about {project}?\n\nCheers,\n{my name}",
            label: "Meeting request (template)"
        ),
        // No abbreviation: Prompt Bank only, picked by typing ;;
        Snippet(abbreviation: "", content: "Review this code for bugs, edge cases and readability. Explain each issue briefly and suggest a fix.", label: "Code review"),
        Snippet(abbreviation: "", content: "Summarise the following in {choice:Length:3 bullet points|one paragraph|one sentence}:\n\n{clipboard}", label: "Summarise clipboard"),
        Snippet(
            abbreviation: "",
            content: "Hi {Client Name},\n\nJust following up on {project}. {cursor}\n\nThanks,\n{my name}\n{company}",
            label: "Follow-up email (template)"
        ),
    ]
}
