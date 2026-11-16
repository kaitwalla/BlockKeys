import AppKit
import Foundation

private final class BlockKeysApp: NSObject, NSApplicationDelegate {
    private let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let blockItem = NSMenuItem(title: "Block internal keyboard when external is connected", action: #selector(toggleBlock), keyEquivalent: "")
    private let mapItem = NSMenuItem(title: "Enable key remapping", action: #selector(toggleMapping), keyEquivalent: "")
    private let stateItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let manager = KeyboardController()
    private let remapper = KeyRemapper()
    private var timer: Timer?

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
        let quit = NSMenuItem(title: "Quit BlockKeys", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        status.menu = menu
        remapper.enabled = UserDefaults.standard.bool(forKey: "remappingEnabled")
        manager.enabled = UserDefaults.standard.bool(forKey: "blockingEnabled")
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
        refresh()
    }

    private func refresh() {
        manager.poll()
        remapper.refresh()
        blockItem.state = manager.enabled ? .on : .off
        mapItem.state = remapper.enabled ? .on : .off
        stateItem.title = manager.status
        status.button?.title = manager.blocked ? "⌨︎×" : "⌨︎"
    }

    @objc private func toggleBlock() {
        manager.enabled.toggle()
        UserDefaults.standard.set(manager.enabled, forKey: "blockingEnabled")
        refresh()
    }

    @objc private func toggleMapping() {
        remapper.enabled.toggle()
        UserDefaults.standard.set(remapper.enabled, forKey: "remappingEnabled")
        refresh()
    }

    @objc private func quit() {
        manager.enabled = false
        manager.poll()
        remapper.enabled = false
        remapper.refresh()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
private let delegate = BlockKeysApp()
app.delegate = delegate
app.run()
