import AppKit
import Observation
import ServiceManagement
import ShorthandCore

/// Ties the snippet store to the keystroke monitor and tracks permission state.
@MainActor
@Observable
final class AppModel {
    let store = SnippetStore()

    var isPaused = false {
        didSet { monitor.isPaused = isPaused }
    }
    private(set) var isTrusted = false
    private(set) var isListening = false
    private(set) var isSecureInputOn = false

    var opensAtLogin: Bool {
        get { loginItemEnabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Shorthand: couldn't change login item: \(error)")
            }
            loginItemEnabled = SMAppService.mainApp.status == .enabled
        }
    }
    private var loginItemEnabled = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private let monitor = KeyMonitor()
    @ObservationIgnored private var timer: Timer?

    init() {
        monitor.matcher = AbbreviationMatcher(snippets: store.snippets)
        monitor.onMatch = { Expander.expand($0) }
        monitor.onPromptBankTrigger = { [store] in Expander.openPromptBank(store.snippets) }
        store.onChange = { [monitor] in monitor.matcher = AbbreviationMatcher(snippets: $0) }
        Expander.variables = store.variableValues
        store.onVariablesChange = { Expander.variables = Variable.lookup($0) }

        // Shows the system Accessibility prompt on first launch.
        _ = Permissions.isTrusted(prompt: true)
        refresh()
        // Picks up the permission once it's granted, and keeps the Secure Input status current.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        isTrusted = Permissions.isTrusted(prompt: false)
        if isTrusted && !monitor.isRunning { monitor.start() }
        isListening = monitor.isRunning
        isSecureInputOn = Permissions.isSecureInputOn
    }
}
