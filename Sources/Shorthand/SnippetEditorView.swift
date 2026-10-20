import ShorthandCore
import SwiftUI

struct SnippetEditorView: View {
    @Bindable var store: SnippetStore
    @State private var selection: Snippet.ID?
    @State private var search = ""
    @State private var showsVariables = false

    private var filtered: [Snippet] {
        guard !search.isEmpty else { return store.snippets }
        return store.snippets.filter {
            $0.abbreviation.localizedCaseInsensitiveContains(search)
                || $0.label.localizedCaseInsensitiveContains(search)
                || $0.content.localizedCaseInsensitiveContains(search)
        }
    }

    // A snippet with no abbreviation belongs to the Prompt Bank.
    private var shortcuts: [Snippet] { filtered.filter { !$0.abbreviation.isEmpty } }
    private var prompts: [Snippet] { filtered.filter { $0.abbreviation.isEmpty } }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Shortcuts") {
                    ForEach(shortcuts) { SnippetRow(snippet: $0) }
                }
                Section {
                    ForEach(prompts) { SnippetRow(snippet: $0) }
                } header: {
                    Text("Prompt Bank")
                } footer: {
                    Text("No shortcut. Type \(PromptBank.trigger) anywhere to pick one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search snippets")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                Menu {
                    Button("New Shortcut") { add(abbreviation: ";") }
                        .keyboardShortcut("n")
                    Button("New Prompt") { add(abbreviation: "") }
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                } label: {
                    Label("New", systemImage: "plus")
                } primaryAction: {
                    add(abbreviation: ";")
                }
                Button {
                    showsVariables = true
                } label: {
                    Label("Variables", systemImage: "curlybraces")
                }
                .help("Values filled in automatically, like {company}")
            }
        } detail: {
            if let id = selection, let binding = binding(for: id) {
                SnippetDetailView(
                    snippet: binding,
                    isDuplicate: store.duplicateAbbreviations.contains(binding.wrappedValue.abbreviation),
                    variableNames: store.variableValues.keys.sorted(),
                    onEditVariables: { showsVariables = true },
                    onDelete: {
                        selection = nil
                        store.delete(id: id)
                    }
                )
                .id(id)
            } else {
                ContentUnavailableView(
                    "No Snippet Selected",
                    systemImage: "text.cursor",
                    description: Text("Pick a snippet. ⌘N adds a shortcut, ⇧⌘N a Prompt Bank prompt.")
                )
            }
        }
        .navigationTitle("Snippets")
        .sheet(isPresented: $showsVariables) {
            VariablesView(store: store)
        }
    }

    private func add(abbreviation: String) {
        search = ""
        selection = store.add(abbreviation: abbreviation).id
    }

    /// Looks the snippet up by id on every access, so a deletion can't leave a stale index.
    private func binding(for id: Snippet.ID) -> Binding<Snippet>? {
        guard let current = store.snippets.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { store.snippets.first(where: { $0.id == id }) ?? current },
            set: { newValue in
                if let index = store.snippets.firstIndex(where: { $0.id == id }) {
                    store.snippets[index] = newValue
                }
            }
        )
    }
}

private struct SnippetRow: View {
    let snippet: Snippet

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if snippet.abbreviation.isEmpty {
                let title = PromptBank.title(of: snippet)
                Text(title.isEmpty ? "New Prompt" : title)
                    .foregroundStyle(title.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
            } else {
                Text(snippet.abbreviation)
                    .font(.body.monospaced())
            }
            Text(snippet.label.isEmpty || snippet.abbreviation.isEmpty ? snippet.content.replacingOccurrences(of: "\n", with: " ") : snippet.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .opacity(snippet.isEnabled ? 1 : 0.5)
    }
}

private struct SnippetDetailView: View {
    @Binding var snippet: Snippet
    let isDuplicate: Bool
    let variableNames: [String]
    let onEditVariables: () -> Void
    let onDelete: () -> Void

    /// The fields this snippet will ask for when it's inserted.
    private var askedFor: [FillInField] {
        FillInTemplate(snippet.content, variableNames: Set(variableNames)).fields
    }

    var body: some View {
        Form {
            Section {
                TextField("Abbreviation", text: $snippet.abbreviation, prompt: Text("None: Prompt Bank only"))
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                if isDuplicate {
                    Label("Another snippet uses this abbreviation.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                TextField("Label", text: $snippet.label, prompt: Text("Optional description"))
                Toggle("Enabled", isOn: $snippet.isEnabled)
            } footer: {
                Text(snippet.abbreviation.isEmpty
                    ? "In the Prompt Bank: type \(PromptBank.trigger) anywhere, or use the menu bar, to insert it. Add an abbreviation to make it a shortcut too."
                    : "Expands as soon as you finish typing the abbreviation. Start abbreviations with a character like ; so they don't fire inside normal words. Clear it to keep this in the Prompt Bank only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextEditor(text: $snippet.content)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .frame(minHeight: 160)
            } header: {
                HStack {
                    Text("Content")
                    Spacer()
                    placeholderMenu
                }
            } footer: {
                let fields = askedFor
                Text(fields.isEmpty
                     ? "Inserts straight away: nothing to fill in."
                     : "Asks for: " + fields.map(\.name).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Group {
                    Text("Filled in automatically: " + MacroExpander.placeholders.joined(separator: "  ") + "  plus your variables")
                    Text("Asked for when inserting: any other {Name}, and " + FillInTemplate.placeholders.dropFirst().joined(separator: "  "))
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Snippet", systemImage: "trash")
            }
        }
    }

    /// Adds a placeholder to the end of the content.
    private var placeholderMenu: some View {
        Menu("Add Placeholder") {
            Section("Filled in automatically") {
                Button("Date  {date}") { append("{date}") }
                Button("Time  {time}") { append("{time}") }
                Button("Date as YYYY-MM-DD  {isodate}") { append("{isodate}") }
                Button("Clipboard  {clipboard}") { append("{clipboard}") }
                Button("Cursor position  {cursor}") { append("{cursor}") }
            }
            Section("Your variables") {
                ForEach(variableNames, id: \.self) { name in
                    Button("{\(name)}") { append("{\(name)}") }
                }
                Button("Edit Variables…", action: onEditVariables)
            }
            Section("Asked for when inserting") {
                Button("Text  {Name}") { append("{Name}") }
                Button("Multi-line text  {fill:Notes:multi}") { append("{fill:Notes:multi}") }
                Button("Choice  {choice:Tone:friendly|formal}") { append("{choice:Tone:friendly|formal}") }
                Button("Optional section  {optional:PS}…{/optional}") { append("{optional:PS}{/optional}") }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.caption)
    }

    private func append(_ placeholder: String) {
        snippet.content += placeholder
    }
}

/// The saved variables, edited in a sheet from the toolbar.
private struct VariablesView: View {
    @Bindable var store: SnippetStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if store.variables.isEmpty {
                        Text("No variables yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.variables) { variable in
                        VariableRow(variable: binding(for: variable.id)) {
                            store.variables.removeAll { $0.id == variable.id }
                        }
                    }
                } header: {
                    Text("Variables")
                } footer: {
                    Text("Write {name} in any snippet and it's replaced with the value, no questions asked. Any other {Name} is asked for when the snippet is inserted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Add Variable") {
                    store.variables.append(Variable(name: "", value: ""))
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 560, height: 420)
    }

    /// Looks the variable up by id on every access, so a deletion can't leave a stale index.
    private func binding(for id: Variable.ID) -> Binding<Variable> {
        Binding(
            get: { store.variables.first { $0.id == id } ?? Variable(id: id, name: "", value: "") },
            set: { newValue in
                if let index = store.variables.firstIndex(where: { $0.id == id }) {
                    store.variables[index] = newValue
                }
            }
        )
    }
}

private struct VariableRow: View {
    @Binding var variable: Variable
    let onDelete: () -> Void

    var body: some View {
        HStack {
            TextField("Name", text: $variable.name, prompt: Text("company"))
                .font(.body.monospaced())
                .autocorrectionDisabled()
                .frame(width: 150)
            TextField("Value", text: $variable.value, prompt: Text("Acme Pty Ltd"))
            if let problem = variable.nameProblem {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help(problem)
            }
            Button(action: onDelete) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Delete variable")
        }
        .labelsHidden()
    }
}
