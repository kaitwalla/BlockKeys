import Foundation
import IOKit.hid

// HID remapping is device-specific. CGEventTap only handles the synthetic F18/F19
// signals, so physical external keyboards are untouched in internal-only mode.
final class KeyboardController {
    private let preferences: Preferences
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let internalMatch = "{\"Built-In\":1,\"Transport\":\"FIFO\",\"PrimaryUsagePage\":1,\"PrimaryUsage\":6}"
    private var lastConfiguration: String?
    private var globalMappingActive = false
    private(set) var blocked = false
    private(set) var status = "Starting"

    init(preferences: Preferences) {
        self.preferences = preferences
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: Int(kHIDPage_GenericDesktop),
            kIOHIDDeviceUsageKey: Int(kHIDUsage_GD_Keyboard)
        ] as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func internalDevice(_ device: IOHIDDevice) -> Bool {
        guard let builtin = IOHIDDeviceGetProperty(device, "Built-In" as CFString) as? NSNumber,
              builtin.boolValue else { return false }
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String
        return transport == "FIFO"
    }

    private func runHidutil(_ mappings: [[String: UInt64]], matching: String?) -> Bool {
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        var arguments = ["property"]
        if let matching { arguments += ["--matching", matching] }
        guard let data = try? JSONSerialization.data(withJSONObject: ["UserKeyMapping": mappings]),
              let json = String(data: data, encoding: .utf8) else { return false }
        arguments += ["--set", json]
        command.arguments = arguments
        command.standardOutput = FileHandle.nullDevice
        command.standardError = FileHandle.nullDevice
        do {
            try command.run()
            command.waitUntilExit()
            return command.terminationStatus == 0
        } catch { return false }
    }

    private func mapping(_ source: Int, _ target: Int) -> [String: UInt64] {
        ["HIDKeyboardModifierMappingSrc": (UInt64(7) << 32) | UInt64(source),
         "HIDKeyboardModifierMappingDst": (UInt64(7) << 32) | UInt64(target)]
    }

    private func customMappings() -> [[String: UInt64]] {
        guard preferences.remapping else { return [] }
        var used = Set<Int>()
        return preferences.rules.compactMap { rule in
            guard rule.enabled, !used.contains(rule.source) else { return nil }
            used.insert(rule.source)
            let destination: Int
            switch rule.target {
            case "meh": destination = 0x6D  // F18, virtual keycode 79
            case "hyper": destination = 0x6E // F19, virtual keycode 80
            case "disabled": destination = 0
            default:
                guard rule.target.hasPrefix("key:"), let target = Int(rule.target.dropFirst(4)) else { return nil }
                destination = target
            }
            return mapping(rule.source, destination)
        }
    }

    private func blockingMappings() -> [[String: UInt64]] {
        (4...231).map { mapping($0, 0) }
    }

    func poll() {
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let internalPresent = devices.contains(where: internalDevice)
        let externalPresent = devices.contains { !internalDevice($0) }
        let shouldBlock = preferences.blocking && internalPresent && externalPresent
        let custom = customMappings()
        let global = preferences.scope == "all" ? custom : []
        let local = shouldBlock ? blockingMappings() : custom
        let signature = "\(shouldBlock)|\(preferences.scope)|\(preferences.remapping)|\(preferences.rules)|\(internalPresent)|\(externalPresent)"

        if signature != lastConfiguration {
            // Clear global overrides when switching back to built-in-only mode.
            if !global.isEmpty || globalMappingActive {
                guard runHidutil(global, matching: nil) else {
                    status = "Failed to update global mappings"
                    return
                }
                globalMappingActive = !global.isEmpty
            }
            if internalPresent {
                guard runHidutil(local, matching: internalMatch) else {
                    status = "Failed to update internal mappings"
                    return
                }
            }
            blocked = shouldBlock
            lastConfiguration = signature
        }
        if blocked { status = "Internal keyboard blocked" }
        else if !preferences.blocking { status = "Keyboard blocking disabled" }
        else if !externalPresent { status = "Waiting for external keyboard" }
        else { status = "Internal keyboard not detected" }
    }

    func restore() {
        _ = runHidutil([], matching: internalMatch)
        if globalMappingActive { _ = runHidutil([], matching: nil) }
        blocked = false
        globalMappingActive = false
        lastConfiguration = nil
    }
}
