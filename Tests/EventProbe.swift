import Foundation
import IOKit.hid

// Diagnostic only. Counts key events from the built-in HID interface, never
// records or prints key codes, characters, or modifier values.
var eventCount = 0
var keyDownCount = 0

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [
    kIOHIDDeviceUsagePageKey: Int(kHIDPage_GenericDesktop),
    kIOHIDDeviceUsageKey: Int(kHIDUsage_GD_Keyboard)
] as CFDictionary)
guard IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
    fatalError("Cannot open HID manager")
}

let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
let internals = devices.filter {
    let builtIn = IOHIDDeviceGetProperty($0, "Built-In" as CFString)
    return (builtIn as? NSNumber)?.boolValue == true
}
guard internals.count == 1, let device = internals.first else {
    print("Expected one internal keyboard, found \(internals.count); aborting")
    exit(2)
}

let product = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Unknown"
print("Monitoring: \(product)")

IOHIDDeviceRegisterInputValueCallback(device, { _, result, _, value in
    guard result == kIOReturnSuccess else { return }
    eventCount += 1
    let element = IOHIDValueGetElement(value)
    if IOHIDElementGetUsagePage(element) == 7 && IOHIDValueGetIntegerValue(value) != 0 {
        keyDownCount += 1
    }
}, nil)
IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
guard openResult == kIOReturnSuccess else {
    print("Seize failed: \(openResult)")
    exit(3)
}
print("Seized for 8 seconds. Press several keys on the built-in keyboard only.")
fflush(stdout)
RunLoop.current.run(until: Date().addingTimeInterval(8))
IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
print("Released. HID values: \(eventCount); key-down values: \(keyDownCount).")
