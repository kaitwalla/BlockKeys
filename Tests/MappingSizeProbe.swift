import Foundation

// Run with BlockKeys fully quit. Use an external keyboard to advance stages.
// No admin access, launch services, or background processes required.
let matcher = "{\"Built-In\":1,\"Transport\":\"FIFO\",\"PrimaryUsagePage\":1,\"PrimaryUsage\":6}"

func apply(_ usages: [Int]) -> Bool {
    let records: [[String: UInt64]] = usages.map { usage in
        ["HIDKeyboardModifierMappingSrc": (UInt64(7) << 32) | UInt64(usage),
         "HIDKeyboardModifierMappingDst": UInt64(7) << 32]
    }
    guard let bytes = try? JSONSerialization.data(withJSONObject: ["UserKeyMapping": records]),
          let json = String(data: bytes, encoding: .utf8) else { return false }
    let command = Process()
    command.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
    command.arguments = ["property", "--matching", matcher, "--set", json]
    command.standardOutput = FileHandle.nullDevice
    do {
        try command.run()
        command.waitUntilExit()
        return command.terminationStatus == 0
    } catch { return false }
}

defer {
    _ = apply([])
    print("\nOriginal keyboard behavior restored (empty remapping).")
}

for (name, usages) in [
    ("16 mappings", Array(4...19)),
    ("64 mappings", Array(4...67)),
    ("128 mappings", Array(4...131)),
    ("228 mappings", Array(4...231))
] {
    guard apply(usages) else {
        print("Could not apply \(name); stopping.")
        break
    }
    print("\n\(name) applied. Press A on the *MacBook* keyboard, then press Return on the *Keychron* to continue.")
    print("Tell us whether MacBook A typed for this stage. Don't enter passwords.")
    fflush(stdout)
    _ = readLine()
}
