import AppKit
import Foundation
import IOKit.hid

private struct Settings: Codable { var enabled = false }

private func settingsURL() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/BlockKeys/settings.json")
}

private func readSettings(_ url: URL) -> Settings {
    guard let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
    return value
}

private func writeSettings(_ value: Settings, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(value)
    try data.write(to: url, options: .atomic)
}

// The privileged process never forwards keystrokes. It exclusively opens the
// internal keyboard only while an external keyboard is connected and enabled.
private final class KeyboardGuard {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let configuration: URL
    private let status: URL
    private var seized: IOHIDDevice?

    init(configuration: URL, status: URL) {
        self.configuration = configuration
        self.status = status
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                               kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }

    private func isInternal(_ device: IOHIDDevice) -> Bool {
        if let builtIn = property(device, "Built-In") as? Bool { return builtIn }
        if let transport = property(device, kIOHIDTransportKey) as? String {
            return transport == "SPI" || transport == "Internal"
        }
        return false
    }

    func update() {
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let internals = devices.filter(isInternal)
        let externalConnected = devices.contains { !isInternal($0) }
        let shouldBlock = readSettings(configuration).enabled && externalConnected

        // Release before choosing a new device or after any disconnect.
        if let old = seized, (!shouldBlock || !internals.contains(old)) {
            IOHIDDeviceClose(old, IOOptionBits(kIOHIDOptionsTypeNone))
            seized = nil
        }
        if shouldBlock && seized == nil {
            for device in internals {
                if IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice)) == kIOReturnSuccess {
                    seized = device
                    break
                }
            }
        }
        let state = seized != nil ? "blocked" : (shouldBlock ? "failed" : (externalConnected ? "ready" : "no-external"))
        try? state.write(to: status, atomically: true, encoding: .utf8)
    }

    func run() -> Never {
        while true {
            update()
            RunLoop.current.run(until: Date().addingTimeInterval(0.75))
        }
    }
}

private final class MenuController: NSObject, NSApplicationDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let toggle = NSMenuItem(title: "Disable built-in keyboard", action: #selector(toggleEnabled), keyEquivalent: "")
    private let detail = NSMenuItem(title: "Checking helper…", action: nil, keyEquivalent: "")
    private let url = settingsURL()
    private let status: URL
    private var timer: Timer?

    override init() {
        status = URL(fileURLWithPath: "/var/tmp/blockkeys-\(getuid()).status")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        toggle.target = self
        menu.addItem(toggle)
        detail.isEnabled = false
        menu.addItem(detail)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit BlockKeys", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        item.button?.title = "⌨︎"
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    @objc private func toggleEnabled() {
        do { try writeSettings(Settings(enabled: !readSettings(url).enabled), to: url) }
        catch { detail.title = "Cannot save preference: \(error.localizedDescription)" }
        refresh()
    }

    private func refresh() {
        let enabled = readSettings(url).enabled
        toggle.state = enabled ? .on : .off
        let state = (try? String(contentsOf: status, encoding: .utf8)) ?? "helper-offline"
        switch state {
        case "blocked": detail.title = "Built-in keyboard blocked"
        case "ready": detail.title = "External keyboard connected"
        case "no-external": detail.title = "Waiting for external keyboard"
        case "failed": detail.title = "Cannot seize internal keyboard"
        default: detail.title = "Helper not running — run install.sh"
        }
        item.button?.title = enabled && state == "blocked" ? "⌨︎×" : "⌨︎"
    }

    @objc private func quitApp() {
        try? writeSettings(Settings(enabled: false), to: url)
        NSApplication.shared.terminate(nil)
    }
}

if CommandLine.arguments.count >= 4 && CommandLine.arguments[1] == "--helper" {
    KeyboardGuard(configuration: URL(fileURLWithPath: CommandLine.arguments[2]),
                  status: URL(fileURLWithPath: CommandLine.arguments[3])).run()
} else {
    let app = NSApplication.shared
    let delegate = MenuController()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
