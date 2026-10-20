import AppKit
import ShorthandCore
import SwiftUI

/// The floating form that asks for a snippet's fill-in fields, styled like the picker.
/// Calls back once with the values, or nil when cancelled or closed.
@MainActor
final class FillInPanel: FloatingPanel, NSWindowDelegate {
    /// Only one form at a time; a new one cancels the old.
    private static var current: FillInPanel?
    private var completion: ((FillInValues?) -> Void)?

    static func present(_ template: FillInTemplate, title: String, completion: @escaping (FillInValues?) -> Void) {
        current?.finish(with: nil)

        var finish: (FillInValues?) -> Void = { _ in }
        let panel = FillInPanel(rootView: FillInForm(
            title: title,
            fields: template.fields,
            values: template.defaultValues,
            onFinish: { finish($0) }
        ))
        finish = { [weak panel] in panel?.finish(with: $0) }
        panel.delegate = panel
        panel.completion = completion
        current = panel
        panel.show()
    }

    private func finish(with values: FillInValues?) {
        guard let completion else { return }
        self.completion = nil
        if Self.current === self { Self.current = nil }
        close()
        completion(values)
    }

    func windowWillClose(_ notification: Notification) {
        finish(with: nil)
    }
}

private struct FillInForm: View {
    let title: String
    let fields: [FillInField]
    @State var values: FillInValues
    let onFinish: (FillInValues?) -> Void
    @FocusState private var focus: FillInField.ID?

    /// Return makes a new line in a multi-line field, so ⌘Return inserts instead.
    private var hasMultiline: Bool { fields.contains { $0.kind == .multilineText } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 12) {
                ForEach(fields) { field in
                    GridRow {
                        Text(field.name)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: 120, alignment: .trailing)
                        control(for: field)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(18)
            ActionBar(
                status: "\(fields.count) \(fields.count == 1 ? "field" : "fields")",
                actions: [
                    .init(
                        title: "Insert",
                        keys: hasMultiline ? ["⌘", "↵"] : ["↵"],
                        shortcut: hasMultiline ? KeyboardShortcut(.return, modifiers: .command) : .defaultAction
                    ) { onFinish(values) },
                    .init(title: "Cancel", keys: ["esc"], shortcut: .cancelAction) { onFinish(nil) },
                ]
            )
        }
        .frame(width: 540)
        .onAppear {
            focus = fields.first { $0.kind == .text || $0.kind == .multilineText }?.id
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "curlybraces")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text("Fill in to insert")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
    }

    @ViewBuilder
    private func control(for field: FillInField) -> some View {
        switch field.kind {
        case .text:
            TextField(field.name, text: text(field))
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focus, equals: field.id)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .inputBackground()
        case .multilineText:
            TextEditor(text: text(field))
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .focused($focus, equals: field.id)
                .padding(4)
                .frame(height: 80)
                .inputBackground()
        case .choice:
            Picker(field.name, selection: text(field)) {
                ForEach(Array(field.options.enumerated()), id: \.offset) { _, option in
                    Text(option.isEmpty ? " " : option).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        case .optional:
            Toggle("Include", isOn: included(field))
                .toggleStyle(.checkbox)
        }
    }

    private func text(_ field: FillInField) -> Binding<String> {
        Binding(get: { values.text[field.id] ?? "" }, set: { values.text[field.id] = $0 })
    }

    private func included(_ field: FillInField) -> Binding<Bool> {
        Binding(get: { values.included[field.id] ?? true }, set: { values.included[field.id] = $0 })
    }
}

private extension View {
    /// The quiet rounded field background used in the panels.
    func inputBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return background(Color.primary.opacity(0.06), in: shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
    }
}
