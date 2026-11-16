#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Build and install on a Mac running macOS 13 or later." >&2
  exit 1
fi
if [[ "$(id -u)" == 0 ]]; then
  echo "Run this as your normal user; sudo is requested where needed." >&2
  exit 1
fi

root_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
app_dir="/Applications/BlockKeys.app"
bin_dir="/Library/PrivilegedHelperTools"
label="com.blockkeys.helper"
plist_path="/Library/LaunchDaemons/${label}.plist"
config_path="${HOME}/Library/Application Support/BlockKeys/settings.json"
status_path="/var/tmp/blockkeys-$(id -u).status"

swiftc -O -framework AppKit -framework IOKit "${root_dir}/Sources/main.swift" -o "${build_dir}/BlockKeys"
mkdir -p "${build_dir}/BlockKeys.app/Contents/MacOS"
cp "${build_dir}/BlockKeys" "${build_dir}/BlockKeys.app/Contents/MacOS/BlockKeys"
cp "${root_dir}/Info.plist" "${build_dir}/BlockKeys.app/Contents/Info.plist"

mkdir -p "$(dirname "$config_path")"
if [[ ! -e "$config_path" ]]; then
  printf '{"enabled":false}\n' > "$config_path"
fi

cat > "${build_dir}/${label}.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key><array>
    <string>${bin_dir}/BlockKeysHelper</string>
    <string>--helper</string>
    <string>${config_path}</string>
    <string>${status_path}</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/var/log/blockkeys.log</string>
</dict></plist>
PLIST

# Quit any existing copy before replacing the executable.
osascript -e 'tell application "BlockKeys" to quit' 2>/dev/null || true
sudo launchctl bootout system "$plist_path" 2>/dev/null || true
sudo mkdir -p "$bin_dir"
sudo cp "${build_dir}/BlockKeys" "${bin_dir}/BlockKeysHelper"
sudo chown root:wheel "${bin_dir}/BlockKeysHelper"
sudo chmod 755 "${bin_dir}/BlockKeysHelper"
sudo cp "${build_dir}/${label}.plist" "$plist_path"
sudo chown root:wheel "$plist_path"
sudo chmod 644 "$plist_path"
sudo ditto "${build_dir}/BlockKeys.app" "$app_dir"
sudo launchctl bootstrap system "$plist_path"
open "$app_dir"
echo "Installed BlockKeys. Toggle it from the keyboard icon in your menu bar."
