import AppKit
import Foundation
import SwiftUI

private final class BlockKeysApp: NSObject, NSApplicationDelegate {
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let blockItem = NSMenuItem(title: "Block internal keyboard when external is connected", action: #selector(toggleBlock), keyEquivalent: "")
    private let mapItem = NSMenuItem(title: "Enable key remapping", action: #selector(toggleMapping), keyEquivalent: "")
    private let stateItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let preferences = Preferences()
    private lazy var manager = KeyboardController(preferences: preferences)
    private let remapper = KeyRemapper()
    private var timer: Timer?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status.button?.title = "⌨︎"
        blockItem.target = self
        mapItem.target = self
        stateItem.isEnabled = false
        menu.addItem(blockItem)
        menu.addItem(mapItem)
        menu.addItem(.separator())
        menu.addItem(stateItem)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit BlockKeys", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        status.menu = menu
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    private func refresh() {
        manager.poll()
        remapper.enabled = preferences.remapping
        remapper.refresh()
        blockItem.state = preferences.blocking ? .on : .off
        mapItem.state = preferences.remapping ? .on : .off
        stateItem.title = manager.status
        status.button?.title = manager.blocked ? "⌨︎×" : "⌨︎"
    }

    @objc private func toggleBlock() {
        preferences.blocking.toggle()
        refresh()
    }

    @objc private func toggleMapping() {
        preferences.remapping.toggle()
        refresh()
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 530),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "BlockKeys Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView(preferences: preferences))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard manager.restore() else {
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Cannot safely quit BlockKeys"
            alert.informativeText = "The built-in keyboard mapping could not be verified as cleared. Keep an external keyboard connected. You can disable blocking and retry, or restore the keyboard in Terminal with hidutil."
            alert.addButton(withTitle: "Keep BlockKeys Running")
            alert.runModal()
            stateItem.title = manager.status
            return .terminateCancel
        }
        remapper.enabled = false
        remapper.refresh()
        return .terminateNow
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
private let delegate = BlockKeysApp()
app.delegate = delegate
app.run()
