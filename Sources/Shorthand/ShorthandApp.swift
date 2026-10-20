import ShorthandCore
import SwiftUI

@main
struct ShorthandApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Shorthand", systemImage: model.isPaused ? "text.badge.xmark" : "text.badge.plus") {
            MenuContent(model: model)
        }

        Window("Snippets", id: "snippets") {
            SnippetEditorView(store: model.store)
        }
        .defaultSize(width: 760, height: 480)
    }
}

struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !model.isTrusted {
            Text("Shorthand needs Accessibility access")
            Button("Open Accessibility Settings…") { Permissions.openAccessibilitySettings() }
            Divider()
        } else if !model.isListening {
            Text("Couldn't start listening for keys")
            Divider()
        } else if model.isSecureInputOn {
            Text("Paused: another app has Secure Input on")
            Divider()
        }

        Menu("Prompt Bank") {
            let prompts = PromptBank.entries(in: model.store.snippets)
            if prompts.isEmpty {
                Text("No prompts yet")
            }
            ForEach(prompts) { snippet in
                Button(PromptBank.title(of: snippet)) {
                    // Wait for the menu to close so the paste lands in the app you were using.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { Expander.insert(snippet) }
                }
            }
            Divider()
            Text("Tip: type \(PromptBank.trigger) anywhere to search")
        }
        Divider()
        Toggle("Pause Expansion", isOn: $model.isPaused)
        Toggle("Open at Login", isOn: $model.opensAtLogin)
        Divider()
        Button("Edit Snippets…") {
            openWindow(id: "snippets")
            NSApp.activate()
        }
        .keyboardShortcut(",")
        Divider()
        Button("Quit Shorthand") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
