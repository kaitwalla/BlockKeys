import Foundation
import SwiftUI

struct KeyChoice: Identifiable {
    let usage: Int
    let name: String
    var id: Int { usage }
}

enum KeyCatalog {
    static let keys: [KeyChoice] = {
        var result = [
            KeyChoice(usage: 0x29, name: "Escape"),
            KeyChoice(usage: 0x39, name: "Caps Lock"),
            KeyChoice(usage: 0xE7, name: "Right Command"),
            KeyChoice(usage: 0xE3, name: "Left Command"),
            KeyChoice(usage: 0xE0, name: "Left Control"),
            KeyChoice(usage: 0xE4, name: "Right Control"),
            KeyChoice(usage: 0xE2, name: "Left Option"),
            KeyChoice(usage: 0xE6, name: "Right Option"),
            KeyChoice(usage: 0xE1, name: "Left Shift"),
            KeyChoice(usage: 0xE5, name: "Right Shift"),
            KeyChoice(usage: 0x2C, name: "Space"),
            KeyChoice(usage: 0x28, name: "Return"),
            KeyChoice(usage: 0x2A, name: "Delete"),
            KeyChoice(usage: 0x2B, name: "Tab"),
            KeyChoice(usage: 0x4F, name: "Right Arrow"),
            KeyChoice(usage: 0x50, name: "Left Arrow"),
            KeyChoice(usage: 0x51, name: "Down Arrow"),
            KeyChoice(usage: 0x52, name: "Up Arrow")
        ]
        for (index, letter) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            result.append(KeyChoice(usage: 0x04 + index, name: String(letter)))
        }
        for (index, digit) in "1234567890".enumerated() {
            result.append(KeyChoice(usage: 0x1E + index, name: String(digit)))
        }
        for i in 1...12 {
            result.append(KeyChoice(usage: 0x39 + i, name: "F\(i)"))
        }
        return result
    }()

    static func name(for usage: Int) -> String {
        keys.first(where: { $0.usage == usage })?.name ?? String(format: "HID 0x%02X", usage)
    }
}

struct RemapRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var source: Int
    // "key:<usage>", "meh", "hyper", "disabled".
    var target: String
    var enabled = true
}

struct SavedPreferences: Codable {
    var blocking = false
    var remapping = false
    var scope = "internal"
    var rules: [RemapRule] = [
        RemapRule(source: 0x39, target: "key:41"), // Caps → Escape
        RemapRule(source: 0x29, target: "meh"),
        RemapRule(source: 0xE7, target: "hyper")
    ]
}

final class Preferences: ObservableObject {
    @Published var blocking: Bool { didSet { save() } }
    @Published var remapping: Bool { didSet { save() } }
    @Published var scope: String { didSet { save() } }
    @Published var rules: [RemapRule] { didSet { save() } }

    init() {
        let existing = UserDefaults.standard.data(forKey: "configuration")
        let saved = existing.flatMap { try? JSONDecoder().decode(SavedPreferences.self, from: $0) } ?? SavedPreferences()
        blocking = saved.blocking
        remapping = saved.remapping
        scope = saved.scope
        rules = saved.rules
    }

    private func save() {
        let snapshot = SavedPreferences(blocking: blocking, remapping: remapping, scope: scope, rules: rules)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: "configuration")
        }
    }
}
