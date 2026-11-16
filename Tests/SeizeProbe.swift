import Foundation
import IOKit.hid

// Temporary, bounded hardware test. Does not install a driver or daemon.
// Run from an external keyboard; the target is released after five seconds.
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [
    kIOHIDDeviceUsagePageKey: Int(kHIDPage_GenericDesktop),
    kIOHIDDeviceUsageKey: Int(kHIDUsage_GD_Keyboard)
] as CFDictionary)

guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
    fatalError("Unable to open HID manager")
}
defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
let builtIn = devices.filter { device in
    let property = IOHIDDeviceGetProperty(device, "Built-In" as CFString)
    return (property as? NSNumber)?.boolValue == true
}

guard builtIn.count == 1, let target = builtIn.first else {
    print("Expected exactly one internal keyboard HID interface; found \(builtIn.count). Nothing seized.")
    exit(2)
}

let name = (IOHIDDeviceGetProperty(target, kIOHIDProductKey as CFString) as? String) ?? "Unknown"
print("Target: \(name)")
print("Attempting exclusive keyboard access for five seconds…")
fflush(stdout)

let result = IOHIDDeviceOpen(target, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
guard result == kIOReturnSuccess else {
    print("Seize failed: IOReturn \(result) (0x\(String(UInt32(bitPattern: result), radix: 16)))")
    exit(3)
}

print("SEIZED. Try pressing keys on the internal keyboard; external keyboard should still work.")
fflush(stdout)
sleep(5)
IOHIDDeviceClose(target, IOOptionBits(kIOHIDOptionsTypeNone))
print("RELEASED. Internal keyboard should work again.")
