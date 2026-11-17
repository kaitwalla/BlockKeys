#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Build on macOS 13 or newer." >&2
  exit 1
fi

project_dir="$(cd "$(dirname "$0")" && pwd)"
application_dir="${HOME}/Applications/BlockKeys.app"
if /usr/bin/pgrep -f '/Applications/BlockKeys\.app/Contents/MacOS/BlockKeys' >/dev/null; then
  echo "Quit BlockKeys from its menu before installing, so it can restore the internal keyboard." >&2
  exit 1
fi

build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
swiftc -O -framework AppKit -framework IOKit \
  "${project_dir}"/Sources/*.swift \
  -o "${build_dir}/BlockKeys"
mkdir -p "${application_dir}/Contents/MacOS"
/usr/bin/install -m 755 "${build_dir}/BlockKeys" "${application_dir}/Contents/MacOS/BlockKeys"
cp "${project_dir}/Info.plist" "${application_dir}/Contents/Info.plist"
codesign --force --sign - "${application_dir}"
open "${application_dir}"
echo "Installed in ${application_dir}. Enable Accessibility permission when prompted."
