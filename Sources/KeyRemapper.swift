import AppKit
import CoreGraphics
import Foundation

// Experimental CGEventTap remappings. Accessibility permission is required.
// Keycodes: Caps Lock 57, Escape 53, Right Command 54.
final class KeyRemapper {
    private static let syntheticMarker: Int64 = 0x424B5953
    var enabled = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var rightCommandHeld = false
    private var escapeHeld = false

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
        rightCommandHeld = false
        escapeHeld = false
    }

    private func process(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if code == 57 && type == .flagsChanged {
            // Caps generates a flagsChanged event on each press. Emit an Escape
            // press+release and suppress the Caps event itself.
            let flags = event.flags.subtracting(.maskAlphaShift)
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
               let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false) {
                down.flags = flags
                up.flags = flags
                down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
                up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            return nil
        }
        if code == 54 && type == .flagsChanged {
            // Right Command produces flagsChanged on press and release. An
            // explicit state avoids treating a held Left Command as a press.
            rightCommandHeld.toggle()
            event.flags = rewrittenFlags(event.flags)
            return Unmanaged.passUnretained(event)
        }
        if code == 53 && (type == .keyDown || type == .keyUp) {
            escapeHeld = type == .keyDown
            // Escape is an alternate modifier; it sends no literal Escape.
            return nil
        }
        event.flags = rewrittenFlags(event.flags)
        return Unmanaged.passUnretained(event)
    }

    private func rewrittenFlags(_ original: CGEventFlags) -> CGEventFlags {
        var result = original.subtracting(.maskAlphaShift)
        if rightCommandHeld { result.formUnion(hyper) }
        if escapeHeld { result.formUnion(meh) }
        return result
    }
}
