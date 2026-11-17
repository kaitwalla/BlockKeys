#!/bin/bash
# Diagnose whether launchd-owned hidutil can activate the map that BlockKeys
# writes but macOS currently ignores. Does not install a persistent agent.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Run this on the MacBook." >&2
  exit 1
fi

mapping_file="${HOME}/Library/Application Support/BlockKeys/last-internal-mapping.json"
if [[ ! -s "$mapping_file" ]]; then
  echo "No saved map. First enable blocking in BlockKeys with an external keyboard attached." >&2
  exit 1
fi

mapping="$(<"$mapping_file")"
matching='{"Built-In":1,"Transport":"FIFO","PrimaryUsagePage":1,"PrimaryUsage":6}'
label="org.blockkeys.launchd-probe.$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
tmpdir="$(mktemp -d)"

cleanup() {
  /bin/launchctl remove "$label" >/dev/null 2>&1 || true
  /bin/rm -r "$tmpdir"
}
trap cleanup EXIT

echo "Submitting one-shot hidutil job via launchd..."
/bin/launchctl submit -l "$label" -o "$tmpdir/stdout" -e "$tmpdir/stderr" -- \
  /usr/bin/hidutil property --matching "$matching" --set "$mapping"

/bin/sleep 2
if [[ -s "$tmpdir/stdout" ]]; then
  echo "hidutil stdout:"
  /bin/cat "$tmpdir/stdout"
fi
if [[ -s "$tmpdir/stderr" ]]; then
  echo "hidutil stderr:"
  /bin/cat "$tmpdir/stderr"
fi

echo "Now test the MacBook keyboard (Keychron still connected)."
echo "If it blocks, the background-process permission context is our missing piece."
echo "To restore immediately, disable blocking in BlockKeys, or run:"
echo "hidutil property --matching '$matching' --set '{\"UserKeyMapping\":[]}'"
