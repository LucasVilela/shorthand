import AppKit
import SwiftUI

/// A borderless, translucent floating panel in the style of Raycast or Spotlight.
/// It takes the keyboard without making Shorthand the active app, and sits in the
/// upper middle of the screen the mouse is on.
@MainActor
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    // A convenience init, so subclasses keep NSWindow's designated initializers,
    // which AppKit can call on its own.
    convenience init(rootView: some View) {
        self.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        // The SwiftUI content draws the rounded, translucent shape; the shadow follows it.
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        let hosting = NSHostingController(rootView: rootView.panelChrome())
        hosting.sizingOptions = [.preferredContentSize]
        contentViewController = hosting
        setContentSize(hosting.view.fittingSize)
        moveToUpperMiddle()
    }

    func show() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }

    /// Centred horizontally, its top a fifth of the way down the screen.
    private func moveToUpperMiddle() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = frame.size
        let x = visible.midX - size.width / 2
        let y = max(visible.maxY - visible.height * 0.2 - size.height, visible.minY)
        setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }
}

extension View {
    /// Rounded, mostly solid background with a hint of blur and a hairline border,
    /// for `FloatingPanel` content. Solid enough to read over a busy screen.
    func panelChrome() -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return self
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.86))
            .background(VisualEffectBackground())
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// A key shown as a small rounded cap, like ↵ or ⌘.
struct KeyCap: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// The strip along the bottom of a panel: app name on the left, actions with their keys on the right.
struct ActionBar: View {
    struct Action: Identifiable {
        let title: String
        let keys: [String]
        var shortcut: KeyboardShortcut?
        let perform: () -> Void

        var id: String { title }
    }

    var status: String = "Shorthand"
    let actions: [Action]

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 18, height: 18)
            Text(status)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 {
                    Divider().frame(height: 14)
                }
                Button(action: action.perform) {
                    HStack(spacing: 6) {
                        Text(action.title)
                            .font(.system(size: 12, weight: index == 0 ? .semibold : .regular))
                            .foregroundStyle(index == 0 ? .primary : .secondary)
                        HStack(spacing: 3) {
                            ForEach(action.keys, id: \.self) { KeyCap($0) }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(action.shortcut)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Color.primary.opacity(0.03))
        .overlay(alignment: .top) { Divider() }
    }
}
