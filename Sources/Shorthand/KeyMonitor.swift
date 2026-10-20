import AppKit
import CoreGraphics
import ShorthandCore

/// Watches every key press system-wide through a Core Graphics event tap and
/// reports when the text typed so far ends with a snippet's abbreviation
/// or with the Prompt Bank trigger, and when the clipboard history hotkey (⌥⌘V) is pressed.
/// Needs Accessibility permission; `start()` fails without it.
@MainActor
final class KeyMonitor {
    var matcher = AbbreviationMatcher(snippets: [])
    var isPaused = false {
        didSet { buffer.reset() }
    }
    var onMatch: ((Snippet) -> Void)?
    var onPromptBankTrigger: (() -> Void)?
    var onClipboardHotkey: (() -> Void)?

    private var buffer = TypingBuffer()
    private var tap: CFMachPort?

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }

        // The tap runs on the main run loop, so the callback is on the main thread.
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            let swallow = MainActor.assumeIsolated { monitor.handle(type, event) }
            // Returning nil drops the event, so the app never sees it.
            return swallow ? nil : Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    /// Returns true to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS switches the tap off if a callback is ever slow; turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .keyDown:
            break
        default:
            // A click can move the caret, so what we buffered no longer applies.
            buffer.reset()
            return false
        }

        // Skip the keys we post ourselves while expanding.
        if event.getIntegerValueField(.eventSourceUserData) == Expander.eventTag { return false }

        // Works even while expansion is paused: it's a separate feature.
        if isClipboardHotkey(event) {
            buffer.reset()
            DispatchQueue.main.async { [onClipboardHotkey] in onClipboardHotkey?() }
            return true
        }

        if isPaused || isTypingIntoShorthand { return false }

        if event.flags.contains(.maskCommand) || event.flags.contains(.maskControl) {
            buffer.reset()
            return false
        }

        switch event.getIntegerValueField(.keyboardEventKeycode) {
        case KeyCode.delete:
            buffer.deleteBackward()
            return false
        case KeyCode.return, KeyCode.enter, KeyCode.tab, KeyCode.escape, KeyCode.forwardDelete,
             KeyCode.leftArrow, KeyCode.rightArrow, KeyCode.upArrow, KeyCode.downArrow,
             KeyCode.home, KeyCode.end, KeyCode.pageUp, KeyCode.pageDown:
            buffer.reset()
            return false
        default:
            break
        }

        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: characters.count, actualStringLength: &length, unicodeString: &characters)
        // Dead keys (the first half of an accented letter) produce nothing yet.
        guard length > 0 else { return false }
        buffer.append(String(utf16CodeUnits: characters, count: length))

        // Let this last key reach the app before we start deleting what was typed.
        if let snippet = matcher.match(in: buffer.text) {
            buffer.reset()
            DispatchQueue.main.async { [onMatch] in onMatch?(snippet) }
        } else if buffer.text.hasSuffix(PromptBank.trigger) {
            buffer.reset()
            DispatchQueue.main.async { [onPromptBankTrigger] in onPromptBankTrigger?() }
        }
        return false
    }

    /// ⌥⌘V, with no Shift or Control.
    private func isClipboardHotkey(_ event: CGEvent) -> Bool {
        let flags = event.flags
        return event.getIntegerValueField(.keyboardEventKeycode) == KeyCode.v
            && flags.contains(.maskCommand) && flags.contains(.maskAlternate)
            && !flags.contains(.maskShift) && !flags.contains(.maskControl)
    }

    /// Typing an abbreviation into Shorthand's own editor, fill-in form or picker shouldn't expand it.
    /// The floating panels can have the keyboard while another app is still frontmost.
    private var isTypingIntoShorthand: Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            || NSApp.keyWindow != nil
    }
}

/// Virtual key codes from the US-layout key positions (Carbon's kVK_* values).
enum KeyCode {
    static let v: Int64 = 9
    static let `return`: Int64 = 36
    static let tab: Int64 = 48
    static let delete: Int64 = 51
    static let escape: Int64 = 53
    static let enter: Int64 = 76
    static let home: Int64 = 115
    static let pageUp: Int64 = 116
    static let forwardDelete: Int64 = 117
    static let end: Int64 = 119
    static let pageDown: Int64 = 121
    static let leftArrow: Int64 = 123
    static let rightArrow: Int64 = 124
    static let downArrow: Int64 = 125
    static let upArrow: Int64 = 126
}
