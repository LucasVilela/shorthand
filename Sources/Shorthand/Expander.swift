import AppKit
import CoreGraphics
import ShorthandCore

/// Replaces a just-typed abbreviation with its snippet in whatever app has focus:
/// asks for any fill-in fields, backspaces over the abbreviation, pastes the
/// snippet, then puts the caret at `{cursor}` and restores the clipboard.
@MainActor
enum Expander {
    /// Stamped on every event we post so `KeyMonitor` can ignore them.
    static let eventTag: Int64 = 0x5348_5254 // "SHRT"
    /// Saved variables by name, kept current by `AppModel`.
    static var variables: [String: String] = [:]

    static func expand(_ snippet: Snippet) {
        insert(snippet, replacing: snippet.abbreviation.count)
    }

    /// Shows the Prompt Bank picker for the just-typed trigger. Picking something deletes
    /// the trigger and inserts (or copies) it; Esc goes back leaving the trigger as typed.
    static func openPromptBank(_ snippets: [Snippet]) {
        let target = NSWorkspace.shared.frontmostApplication
        PromptPickerPanel.present(snippets, variableNames: Set(variables.keys)) { choice in
            guard let target, !target.isTerminated else { return }
            reactivate(target) {
                switch choice {
                case .insert(let snippet):
                    insert(snippet, replacing: PromptBank.trigger.count)
                case .copy(let snippet):
                    press(KeyCode.delete, times: PromptBank.trigger.count)
                    copy(snippet)
                case nil:
                    break
                }
            }
        }
    }

    /// Shows clipboard history over the frontmost app. Paste puts the entry on the
    /// clipboard and pastes it there; Copy only puts it on the clipboard.
    static func openClipboardHistory(_ store: ClipboardHistoryStore, saveAsPrompt: @escaping @MainActor (String) -> Void) {
        let target = NSWorkspace.shared.frontmostApplication
        ClipboardHistoryPanel.present(store) { choice in
            guard let choice else {
                if let target, !target.isTerminated { reactivate(target) {} }
                return
            }
            if case .saveAsPrompt(let text) = choice {
                saveAsPrompt(text)
            }
            guard let target, !target.isTerminated else { return }
            reactivate(target) {
                switch choice {
                case .paste(let text):
                    // Not marked transient: pasting an old entry makes it the newest.
                    putOnClipboard(text)
                    press(KeyCode.v, flags: .maskCommand)
                case .copy(let text):
                    putOnClipboard(text)
                case .saveAsPrompt:
                    break
                }
            }
        }
    }

    private static func putOnClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Inserts `snippet` at the caret of the frontmost app, after deleting the `count`
    /// characters just typed (an abbreviation or the trigger).
    static func insert(_ snippet: Snippet, replacing count: Int = 0) {
        withFieldValues(for: snippet) { template, values in
            press(KeyCode.delete, times: count)
            paste(template, values: values)
        }
    }

    /// Puts the filled-in snippet on the clipboard instead of typing it.
    static func copy(_ snippet: Snippet) {
        withFieldValues(for: snippet) { template, values in
            let pasteboard = NSPasteboard.general
            let text = MacroExpander(clipboard: pasteboard.string(forType: .string) ?? "", variables: variables)
                .expand(template, values: values).text
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }

    /// Calls `then` with the snippet's fill-in values: straight away when it has no fields,
    /// otherwise once the form is submitted and focus is back in the app that was frontmost.
    /// Anything typed is deleted only then, so the backspaces reach that app and not the form.
    private static func withFieldValues(
        for snippet: Snippet,
        then action: @escaping @MainActor (FillInTemplate, FillInValues) -> Void
    ) {
        let template = FillInTemplate(snippet.content, variableNames: Set(variables.keys))
        guard !template.fields.isEmpty else {
            action(template, FillInValues())
            return
        }
        let target = NSWorkspace.shared.frontmostApplication
        FillInPanel.present(template, title: PromptBank.title(of: snippet)) { values in
            guard let target, !target.isTerminated else { return }
            // Cancelling still hands focus back, leaving what was typed alone.
            reactivate(target) {
                if let values { action(template, values) }
            }
        }
    }

    private static func paste(_ template: FillInTemplate, values: FillInValues) {
        let pasteboard = NSPasteboard.general
        let result = MacroExpander(clipboard: pasteboard.string(forType: .string) ?? "", variables: variables).expand(template, values: values)
        let snapshot = PasteboardSnapshot(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(result.text, forType: .string)
        // Tells clipboard managers not to record this temporary copy (nspasteboard.org).
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let ourChangeCount = pasteboard.changeCount

        press(KeyCode.v, flags: .maskCommand)
        press(KeyCode.leftArrow, times: result.cursorOffsetFromEnd)

        // The target app reads the clipboard when it handles ⌘V, which can lag a bit.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // If something else was copied meanwhile, leave it alone.
            guard pasteboard.changeCount == ourChangeCount else { return }
            snapshot.restore(to: pasteboard)
        }
    }

    /// Hands focus back to `app` and runs `then` once it's frontmost (or after about a second).
    private static func reactivate(_ app: NSRunningApplication, then action: @escaping @MainActor () -> Void) {
        if NSRunningApplication.current.isActive {
            NSApp.yieldActivation(to: app)
            app.activate(from: .current, options: [])
        }
        waitUntilFrontmost(app, attemptsLeft: 20, then: action)
    }

    private static func waitUntilFrontmost(_ app: NSRunningApplication, attemptsLeft: Int, then action: @escaping @MainActor () -> Void) {
        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Once it's frontmost, the extra beat lets its window become key again.
            if isFrontmost || attemptsLeft == 0 {
                action()
            } else {
                waitUntilFrontmost(app, attemptsLeft: attemptsLeft - 1, then: action)
            }
        }
    }

    private static func press(_ keyCode: Int64, flags: CGEventFlags = [], times: Int = 1) {
        guard times > 0 else { return }
        let source = CGEventSource(stateID: .privateState)
        for _ in 0..<times {
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: isDown) else { continue }
                // Set explicitly so modifiers the user is still holding don't leak in.
                event.flags = flags
                event.setIntegerValueField(.eventSourceUserData, value: eventTag)
                event.post(tap: .cghidEventTap)
            }
        }
    }
}

/// A copy of everything on the clipboard (all items, all types) so it can be put back.
private struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                data[type] = item.data(forType: type)
            }
            return data
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { entries in
            let item = NSPasteboardItem()
            for (type, data) in entries {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
