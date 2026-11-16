import Foundation
import IOKit.hid

final class KeyboardController {
    var enabled = false
    private(set) var blocked = false
    private(set) var status = "Waiting for external keyboard"
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private let match = "{\"Built-In\":1,\"Transport\":\"FIFO\",\"PrimaryUsagePage\":1,\"PrimaryUsage\":6}"
    private var lastCommandFailed = false

    init() {
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDDeviceUsagePageKey: Int(kHIDPage_GenericDesktop),
            kIOHIDDeviceUsageKey: Int(kHIDUsage_GD_Keyboard)
        ] as CFDictionary)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func isInternal(_ device: IOHIDDevice) -> Bool {
        guard let builtIn = IOHIDDeviceGetProperty(device, "Built-In" as CFString) as? NSNumber,
              builtIn.boolValue else { return false }
        guard let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String else { return false }
        return transport == "FIFO"
    }

    private func runHidutil(_ json: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        task.arguments = ["property", "--matching", match, "--set", json]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch { return false }
    }

    private func setBlocked(_ value: Bool) -> Bool {
        if !value { return runHidutil("{\"UserKeyMapping\":[]}") }
        // Standard keyboard usages, including letters, navigation and modifiers.
        // Vendor-specific keys may require separate treatment.
        let mappings = (4...231).map { usage in
            ["HIDKeyboardModifierMappingSrc": (UInt64(7) << 32) | UInt64(usage),
             "HIDKeyboardModifierMappingDst": UInt64(7) << 32]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ["UserKeyMapping": mappings]),
              let json = String(data: data, encoding: .utf8) else { return false }
        return runHidutil(json)
    }

    func poll() {
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        let haveInternal = devices.contains(where: isInternal)
        let haveExternal = devices.contains { !isInternal($0) }
        let desired = enabled && haveInternal && haveExternal
        if desired != blocked {
            let succeeded = setBlocked(desired)
            if succeeded { blocked = desired }
            lastCommandFailed = !succeeded
        }
        if lastCommandFailed { status = "hidutil failed — check Terminal" }
        else if blocked { status = "Internal keyboard blocked (experimental)" }
        else if !enabled { status = "Keyboard blocking disabled" }
        else if !haveExternal { status = "Waiting for external keyboard" }
        else { status = "Internal keyboard not detected" }
    }
}
