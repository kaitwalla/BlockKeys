import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section("Features") {
                Toggle("Disable built-in keyboard while an external keyboard is connected", isOn: $preferences.blocking)
                Toggle("Enable custom key remappings", isOn: $preferences.remapping)
            }
            Section("Remapping scope") {
                Picker("Apply mappings to", selection: $preferences.scope) {
                    Text("Built-in keyboard only").tag("internal")
                    Text("All keyboards").tag("all")
                }
                .pickerStyle(.radioGroup)
                Text("Keyboard blocking always applies only to the built-in keyboard.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("Key mappings") {
                ForEach($preferences.rules) { $rule in
                    HStack {
                        Toggle("", isOn: $rule.enabled).labelsHidden()
                        Picker("From", selection: $rule.source) {
                            ForEach(KeyCatalog.keys) { key in
                                Text(key.name).tag(key.usage)
                            }
                        }
                        .labelsHidden().frame(width: 155)
                        Image(systemName: "arrow.right")
                        Picker("To", selection: $rule.target) {
                            Text("Escape").tag("key:41")
                            Text("Meh (⌃⌥⇧)").tag("meh")
                            Text("Hyper (⌃⌥⇧⌘)").tag("hyper")
                            Text("Disabled").tag("disabled")
                            Divider()
                            ForEach(KeyCatalog.keys) { key in
                                if key.usage != 0x29 {
                                    Text(key.name).tag("key:\(key.usage)")
                                }
                            }
                        }
                        .labelsHidden().frame(width: 175)
                        Button(role: .destructive) {
                            preferences.rules.removeAll(where: { $0.id == rule.id })
                        } label: { Image(systemName: "minus.circle") }
                    }
                }
                Button("Add mapping") {
                    preferences.rules.append(RemapRule(source: 0x39, target: "key:41"))
                }
            }
            Text("Meh and Hyper use reserved F18/F19 intermediary keys. Avoid assigning those function keys elsewhere. Changes apply automatically.")
                .font(.caption).foregroundColor(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 610, height: 530)
    }
}
