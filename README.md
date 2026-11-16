# BlockKeys

A minimal, dependency-free macOS menu-bar app that disables the internal MacBook keyboard when an external keyboard is connected. Click **⌨︎** in the menu bar to enable or disable the behavior. The default is **off**.

## Build and install

On macOS 13+ with Xcode Command Line Tools installed:

```bash
chmod +x install.sh
./install.sh
```

The installer builds one Swift executable, places a menu-bar app in `/Applications`, and installs a root-owned `launchd` helper. The helper is required for `IOHIDDeviceOpen(..., kIOHIDOptionsTypeSeizeDevice)`. macOS may require you to approve **Input Monitoring** for the helper in **System Settings → Privacy & Security**. The helper polls for setting and device changes; no network access or third-party runtime is used.

The helper automatically releases the internal keyboard if the external keyboard disappears, you switch the feature off, or the helper exits. Quitting the menu-bar app also turns blocking off. For an external Bluetooth keyboard, “connected” means still connected to macOS, even if it is physically elsewhere.

**Important:** This is an untested prototype. It has **not been built or exercised on macOS hardware**. The MacBook's keyboard may share a HID device with the trackpad; this implementation might also suppress the trackpad on some hardware. Keep an external keyboard and pointing device available during testing. Depending on the model, internal keyboard identification or device seizure may fail, in which case the menu displays an error and the built-in keyboard should remain usable.

## Remove

```bash
sudo launchctl bootout system /Library/LaunchDaemons/com.blockkeys.helper.plist
sudo rm /Library/LaunchDaemons/com.blockkeys.helper.plist
sudo rm /Library/PrivilegedHelperTools/BlockKeysHelper
sudo rm -r /Applications/BlockKeys.app
```

Your preference file remains at `~/Library/Application Support/BlockKeys/settings.json` unless you remove it manually.

## Architecture

- **Menu app:** unprivileged AppKit status item, JSON preference toggle.
- **Helper:** privileged IOKit HID manager, polls approximately every 750ms, seizes only a detected internal keyboard while an external keyboard is present and blocking is enabled.
- **Status:** helper writes a short state string to `/var/tmp/blockkeys-UID.status` for the menu-bar display. This is diagnostic only, not a control channel.

## License

MIT (see `LICENSE`).
