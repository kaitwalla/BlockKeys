# BlockKeys

An experimental, dependency-free macOS menu-bar keyboard utility, built for the M5 MacBook Air.

## Features

- **Automatic internal keyboard blocking:** when an external keyboard is connected, BlockKeys uses macOS's `/usr/bin/hidutil` to map standard built-in keyboard usages to undefined HID usage `0x07:0x00`. External keyboards are not remapped. Unplugging the external keyboard restores the internal keyboard.
- **Key remapping:** Caps Lock → Escape, Escape → Meh (Control+Option+Shift), Right Command → Hyper (Control+Option+Shift+Command). Left Command stays normal.
- Independent menu-bar toggles for blocking and remapping. Both features default to **off** on a fresh installation.

## Build and launch (macOS 13+)

```bash
./install.sh
```

This builds and ad-hoc signs `~/Applications/BlockKeys.app`. There are no dependencies outside Apple's command-line tools and no privileged daemon. Approve **Accessibility** for BlockKeys when macOS asks; it is required for modifier interception.

**Do not install the old privileged helper:** it did not actually suppress input on the M5. The new installer does not use `sudo` or install a LaunchDaemon.

## Experimental warnings

This version has not yet been compiled or tested on a Mac by the project maintainers. The single-key `hidutil` test was successful on an M5 MacBook Air, but the **full 228-key mapping and event-tap remaps are not yet validated**.

Keep your Keychron connected for the first tests. To recover the internal keyboard from Terminal, run:

```bash
hidutil property --matching '{"Built-In":1,"Transport":"FIFO","PrimaryUsagePage":1,"PrimaryUsage":6}' --set '{"UserKeyMapping":[]}'
```

Restarting macOS also clears `hidutil` mappings. If the menu app crashes while blocking is on, the remapping may persist until the reset command or restart. Vendor-defined function keys, Touch ID, and some nonstandard keys may not be affected.

The experimental event-tap mappings may not behave correctly inside password prompts or Secure Event Input. Disable the remapping toggle if shortcuts behave unexpectedly. **Quit Superkey first**, to avoid two apps intercepting the same modifiers.

## Implementation

- `Sources/KeyboardController.swift`: HID keyboard discovery and device-specific `hidutil` mappings.
- `Sources/KeyRemapper.swift`: local keyboard event tap for modifier remaps.
- `Sources/main.swift`: minimal AppKit menu-bar application.
- `Tests/`: short-duration hardware probes.

MIT licensed.
