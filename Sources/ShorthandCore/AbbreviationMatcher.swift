/// Finds the snippet whose abbreviation was just typed.
public struct AbbreviationMatcher: Sendable {
    // Longest first, so ";dd" wins over ";d" when both end the typed text.
    private let candidates: [Snippet]

    public init(snippets: [Snippet]) {
        candidates = snippets
            .filter { $0.isEnabled && !$0.abbreviation.isEmpty }
            .sorted { $0.abbreviation.count > $1.abbreviation.count }
    }

    public func match(in typed: String) -> Snippet? {
        candidates.first { typed.hasSuffix($0.abbreviation) }
    }
}
