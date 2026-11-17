# BlockKeys

An experimental, dependency-free macOS menu-bar keyboard utility, built for the M5 MacBook Air.

## Features

- **Automatic internal keyboard blocking:** when an external keyboard is connected, BlockKeys asks `launchd` to run macOS's `hidutil` and map standard built-in keyboard usages to undefined HID usage `0x07:0x00`. External keyboards are not remapped. Unplugging the external keyboard restores the internal keyboard.
- **Wake recovery:** after the Mac wakes from sleep, BlockKeys reapplies the selected mappings as the keyboard services become available again.
- **Key remapping:** customizable source/target pairs, including Escape, Meh (Control+Option+Shift), Hyper (Control+Option+Shift+Command), ordinary keys and disabled keys. Defaults are Caps Lock → Escape, Escape → Meh, and Right Command → Hyper.
- **Scope:** remapping defaults to **built-in keyboard only**, with an option to apply the mappings to all connected keyboards. Keyboard blocking remains built-in-only.
- Independent menu-bar toggles for blocking and remapping. Both features default to **off** on a fresh installation.
- **Settings window:** choose keys, manage rules, and toggle features via **⌨︎ → Settings…**.

## Build and launch (macOS 13+)

```bash
bash install.sh
```

This builds and ad-hoc signs `~/Applications/BlockKeys.app`. There are no dependencies outside Apple's command-line tools, no `sudo`, and no persistent privileged daemon. Approve **Accessibility** for BlockKeys to use its shortcut event tap. If character-key mappings are accepted but ignored, grant **Input Monitoring** to `/usr/bin/hidutil` in System Settings → Privacy & Security. Mapping commands run as transient `launchd` jobs, separate from the app's privacy context.

**Do not install the old privileged helper:** it did not actually suppress input on the M5. The new installer does not use `sudo` or install a LaunchDaemon.

## Experimental warnings

The earlier prototype passed M5 tests for all three key remaps and automatic keyboard blocking/restore. The settings-and-scope implementation exposed a permission-context bug: modifier remaps worked, but ordinary character-key maps applied from the app were silently ineffective. A one-shot `launchd`-owned `hidutil` probe successfully blocked the keyboard on the M5. **The integrated launchd backend still needs testing, especially disconnect/restore and rapid toggles.**

Keep your Keychron connected for the first tests. To recover the internal keyboard from Terminal, run:

```bash
hidutil property --matching '{"Built-In":1,"Transport":"FIFO","PrimaryUsagePage":1,"PrimaryUsage":6}' --set '{"UserKeyMapping":[]}'
```

Restarting macOS also clears `hidutil` mappings. If the menu app crashes while blocking is on, the remapping may persist until the reset command or restart. Vendor-defined function keys, Touch ID, and some nonstandard keys may not be affected.

Normal Quit attempts to clear the keyboard mapping and confirms the empty map with `hidutil` before allowing the app to terminate. If verification fails, BlockKeys stays open and displays an error. This cannot protect against Force Quit, crashes, or power loss; keep the reset command above available.

The device-scoped remapper maps Meh/Hyper sources to intermediary F18/F19 HID keys, which a small event tap interprets. Those two F-keys are reserved while remapping is enabled. The event tap may not behave correctly inside password prompts or Secure Event Input. Disable remapping if shortcuts behave unexpectedly. **Quit Superkey first**, to avoid two apps intercepting the same modifiers.

## Implementation

- `Sources/KeyboardController.swift`: HID keyboard discovery and device-specific mapping management.
- `Sources/KeyRemapper.swift`: local keyboard event tap for modifier remaps.
- `Sources/Configuration.swift`: persisted preferences and key catalog.
- `Sources/SettingsView.swift`: editable settings window.
- `Sources/main.swift`: minimal AppKit menu-bar application.
- `Tests/`: short-duration hardware probes.

MIT licensed.
