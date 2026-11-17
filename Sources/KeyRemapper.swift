import AppKit
import CoreGraphics
import Foundation

// Handles only the F18/F19 sentinel keys emitted by device-specific hidutil
// mappings. Never remaps ordinary external keyboard keys by itself.
final class KeyRemapper {
    var enabled = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var hyperHeld = false
    private var mehHeld = false

    private let meh: CGEventFlags = [.maskControl, .maskAlternate, .maskShift]
    private let hyper: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]

    func refresh() {
        if enabled && tap == nil { start() }
        if !enabled && tap != nil { stop() }
    }

    private func start() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let target = Unmanaged<KeyRemapper>.fromOpaque(info).takeUnretainedValue()
            return target.process(event, type: type)
        }, userInfo: pointer) else { return }
        tap = newTap
        let runSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        source = runSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
    }

    private func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        tap = nil
        hyperHeld = false
        mehHeld = false
    }

    private func process(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if code == 79 && (type == .keyDown || type == .keyUp) {
            mehHeld = type == .keyDown
            return nil
        }
        if code == 80 && (type == .keyDown || type == .keyUp) {
            hyperHeld = type == .keyDown
            return nil
        }
        event.flags = rewrittenFlags(event.flags)
        return Unmanaged.passUnretained(event)
    }

    private func rewrittenFlags(_ original: CGEventFlags) -> CGEventFlags {
        var result = original
        if hyperHeld { result.formUnion(hyper) }
        if mehHeld { result.formUnion(meh) }
        return result
    }
}
