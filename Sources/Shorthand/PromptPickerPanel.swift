import AppKit
import ShorthandCore
import SwiftUI

enum PromptPickerChoice {
    case insert(Snippet)
    case copy(Snippet)
}

/// The Raycast-style launcher that `;;` opens: search, list, preview and actions.
/// Calls back once with what was picked, or nil when dismissed.
@MainActor
final class PromptPickerPanel: FloatingPanel, NSWindowDelegate {
    /// Only one picker at a time; a new one cancels the old.
    private static var current: PromptPickerPanel?
    private var completion: ((PromptPickerChoice?) -> Void)?

    static func present(
        _ snippets: [Snippet],
        variableNames: Set<String>,
        completion: @escaping (PromptPickerChoice?) -> Void
    ) {
        current?.finish(with: nil)

        var finish: (PromptPickerChoice?) -> Void = { _ in }
        let panel = PromptPickerPanel(rootView: PromptPicker(
            snippets: snippets,
            variableNames: variableNames,
            onFinish: { finish($0) }
        ))
        finish = { [weak panel] in panel?.finish(with: $0) }
        panel.delegate = panel
        panel.completion = completion
        current = panel
        panel.show()
    }

    private func finish(with choice: PromptPickerChoice?) {
        guard let completion else { return }
        self.completion = nil
        if Self.current === self { Self.current = nil }
        close()
        completion(choice)
    }

    // Clicking anywhere else dismisses it, like Raycast.
    func windowDidResignKey(_ notification: Notification) {
        finish(with: nil)
    }

    func windowWillClose(_ notification: Notification) {
        finish(with: nil)
    }
}

private struct PromptPicker: View {
    let snippets: [Snippet]
    let variableNames: Set<String>
    let onFinish: (PromptPickerChoice?) -> Void

    @State private var query = ""
    @State private var selectedID: Snippet.ID?
    @FocusState private var isSearchFocused: Bool

    private var results: [Snippet] { PromptBank.search(snippets, for: query) }
    private var prompts: [Snippet] { results.filter { $0.abbreviation.isEmpty } }
    private var shortcuts: [Snippet] { results.filter { !$0.abbreviation.isEmpty } }
    /// Display order, which the arrow keys follow.
    private var ordered: [Snippet] { prompts + shortcuts }

    /// The highlighted row: the one moved to, else the best match.
    private var current: Snippet? {
        let ordered = ordered
        return ordered.first { $0.id == selectedID } ?? ordered.first
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            if let current {
                HStack(spacing: 0) {
                    list
                        .frame(width: 300)
                    Divider()
                    SnippetPreview(snippet: current, variableNames: variableNames)
                }
            } else {
                emptyState
            }
            ActionBar(
                status: "\(ordered.count) \(ordered.count == 1 ? "item" : "items")",
                actions: current.map { snippet in
                    [
                        .init(title: "Insert", keys: ["↵"]) { onFinish(.insert(snippet)) },
                        .init(title: "Copy", keys: ["⌘", "C"], shortcut: KeyboardShortcut("c")) { onFinish(.copy(snippet)) },
                        .init(title: "Close", keys: ["esc"]) { onFinish(nil) },
                    ]
                } ?? [.init(title: "Close", keys: ["esc"]) { onFinish(nil) }]
            )
        }
        .frame(width: 760, height: 460)
        .onAppear { isSearchFocused = true }
    }

    private var searchField: some View {
        TextField("Search prompts and snippets…", text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 20))
            .focused($isSearchFocused)
            .onSubmit {
                if let current { onFinish(.insert(current)) }
            }
            .onKeyPress(.upArrow) { move(by: -1); return .handled }
            .onKeyPress(.downArrow) { move(by: 1); return .handled }
            .onKeyPress(.escape) { onFinish(nil); return .handled }
            .padding(.horizontal, 18)
            .frame(height: 56)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    section("Prompt Bank", prompts)
                    section("Snippets", shortcuts)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
            .onChange(of: selectedID) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ snippets: [Snippet]) -> some View {
        if !snippets.isEmpty {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .padding(.bottom, 4)
            ForEach(snippets) { snippet in
                PickerRow(
                    snippet: snippet,
                    hasFields: !FillInTemplate(snippet.content, variableNames: variableNames).fields.isEmpty,
                    isSelected: snippet.id == current?.id
                )
                .id(snippet.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { onFinish(.insert(snippet)) }
                .onTapGesture { selectedID = snippet.id }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: snippets.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(snippets.contains { $0.isEnabled && !$0.content.isEmpty } ? "No results" : "Nothing here yet")
                .font(.system(size: 14, weight: .medium))
            Text("Add prompts with Edit Snippets… in the menu bar.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func move(by offset: Int) {
        let ordered = ordered
        guard !ordered.isEmpty else { return }
        let index = ordered.firstIndex { $0.id == current?.id } ?? 0
        selectedID = ordered[min(max(index + offset, 0), ordered.count - 1)].id
    }
}

private struct PickerRow: View {
    let snippet: Snippet
    let hasFields: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            SnippetIcon(snippet: snippet, hasFields: hasFields)
            Text(PromptBank.title(of: snippet))
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 8)
            if !snippet.abbreviation.isEmpty {
                Text(snippet.abbreviation)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(
            isSelected ? Color.primary.opacity(0.1) : .clear,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

/// A tinted rounded square: purple speech bubble for prompts, blue for shortcuts,
/// orange braces for anything with fields to fill in.
private struct SnippetIcon: View {
    let snippet: Snippet
    let hasFields: Bool

    private var symbol: String {
        if hasFields { return "curlybraces" }
        return snippet.abbreviation.isEmpty ? "text.bubble.fill" : "text.cursor"
    }

    private var tint: Color {
        if hasFields { return .orange }
        return snippet.abbreviation.isEmpty ? .purple : .blue
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 22, height: 22)
            .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// The right-hand pane: the full text with placeholders highlighted, then details.
private struct SnippetPreview: View {
    let snippet: Snippet
    let variableNames: Set<String>

    private var fields: [FillInField] {
        FillInTemplate(snippet.content, variableNames: variableNames).fields
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                Text(highlighted(snippet.content))
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
            Divider()
            VStack(spacing: 8) {
                detail("Type", snippet.abbreviation.isEmpty ? "Prompt Bank" : "Snippet")
                if !snippet.abbreviation.isEmpty {
                    detail("Shortcut", snippet.abbreviation, monospaced: true)
                }
                detail("Asks for", fields.isEmpty ? "Nothing" : fields.map(\.name).joined(separator: ", "))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private func detail(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 12))
    }

    /// The text with every `{…}` shown as a tinted token.
    private func highlighted(_ content: String) -> AttributedString {
        var result = AttributedString()
        var rest = content[...]
        for match in content.matches(of: /\{[^{}\n]*\}/) {
            result += AttributedString(rest[..<match.range.lowerBound])
            var token = AttributedString(content[match.range])
            token.foregroundColor = .accentColor
            token.backgroundColor = Color.accentColor.opacity(0.12)
            result += token
            rest = content[match.range.upperBound...]
        }
        result += AttributedString(rest)
        return result
    }
}
