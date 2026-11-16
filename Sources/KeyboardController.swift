import Foundation
import IOKit.hid

@_silgen_name("BKApplyHIDMappings")
private func BKApplyHIDMappings(_ json: UnsafePointer<CChar>, _ internalOnly: Int32) -> Int32

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
    private var lastNativeResult: Int32 = 0
    private var lastApplyError = "unknown"

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

    // launchctl submit only confirms that launchd accepted a job; it does not
    // wait for hidutil to finish. Without this barrier, an old toggle can
    // overwrite the latest keyboard map seconds later.
    private func waitForMappingJob(_ label: String) -> Bool {
        let until = Date().addingTimeInterval(3)
        let expression = try! NSRegularExpression(pattern: #"LastExitStatus[^=]*=\s*(-?\d+)"#)
        while Date() < until {
            let check = Process()
            check.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            check.arguments = ["list", label]
            let output = Pipe()
            check.standardOutput = output
            check.standardError = FileHandle.nullDevice
            do {
                try check.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                check.waitUntilExit()
                if check.terminationStatus == 0,
                   let text = String(data: data, encoding: .utf8),
                   let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let range = Range(match.range(at: 1), in: text),
                   let code = Int(text[range]) {
                    if code == 0 { return true }
                    lastApplyError = "hidutil exited \(code)"
                    return false
                }
            } catch {
                lastApplyError = "could not inspect launchd job: \(error.localizedDescription)"
                return false
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        lastApplyError = "hidutil did not finish within 3 seconds"
        return false
    }

    private func runHidutil(_ mappings: [[String: UInt64]], matching: String?) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: ["UserKeyMapping": mappings]),
              let json = String(data: data, encoding: .utf8) else { return false }
        if matching == internalMatch && !mappings.isEmpty {
            // Export exactly the payload sent to hidutil for reproducible
            // Terminal-side diagnostics. Contains HID codes only, no key events.
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/BlockKeys", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: directory.appendingPathComponent("last-internal-mapping.json"), options: .atomic)
        }
        // The direct HID property APIs accept and store character-key maps on
        // current macOS, but don't activate them in BlockKeys' TCC context.
        // launchd-owned hidutil *does* activate the same payload on the M5 Air.
        // Launch it as a short-lived job so Input Monitoring is attributed to
        // /usr/bin/hidutil, not to an inherited app subprocess.
        if ProcessInfo.processInfo.environment["BLOCKKEYS_USE_NATIVE_HID"] == "1" {
            lastNativeResult = json.withCString { BKApplyHIDMappings($0, matching == internalMatch ? 1 : 0) }
            lastApplyError = "native HID result \(lastNativeResult)"
            return lastNativeResult > 0
        }

        let label = "org.blockkeys.mapping.\(UUID().uuidString.lowercased())"
        let logs = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlockKeys-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        } catch {
            lastApplyError = "could not create temporary directory: \(error.localizedDescription)"
            return false
        }
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        var arguments = ["submit", "-l", label,
                         "-o", logs.appendingPathComponent("stdout").path,
                         "-e", logs.appendingPathComponent("stderr").path,
                         "--", "/usr/bin/hidutil", "property"]
        if let matching { arguments += ["--matching", matching] }
        arguments += ["--set", json]
        command.arguments = arguments
        command.standardOutput = FileHandle.nullDevice
        command.standardError = FileHandle.nullDevice
        do {
            try command.run()
            command.waitUntilExit()
            guard command.terminationStatus == 0 else {
                lastApplyError = "launchctl exited \(command.terminationStatus)"
                try? FileManager.default.removeItem(at: logs)
                return false
            }
            // Remove the completed job after the next command can no longer
            // race with it. A timer also cleans up failed/timed-out jobs.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                let cleanup = Process()
                cleanup.executableURL = URL(fileURLWithPath: "/bin/launchctl")
                cleanup.arguments = ["remove", label]
                cleanup.standardOutput = FileHandle.nullDevice
                cleanup.standardError = FileHandle.nullDevice
                if (try? cleanup.run()) != nil { cleanup.waitUntilExit() }
                try? FileManager.default.removeItem(at: logs)
            }
            return waitForMappingJob(label)
        } catch {
            lastApplyError = "launchctl could not start: \(error.localizedDescription)"
            try? FileManager.default.removeItem(at: logs)
            return false
        }
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
                    status = "HID global mapping failed (\(lastApplyError))"
                    return
                }
                globalMappingActive = !global.isEmpty
            }
            if internalPresent {
                guard runHidutil(local, matching: internalMatch) else {
                    status = "HID internal mapping failed (\(lastApplyError))"
                    return
                }
            }
            blocked = shouldBlock
            lastConfiguration = signature
        }
        if blocked { status = "Internal blocking requested via launchd" }
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
