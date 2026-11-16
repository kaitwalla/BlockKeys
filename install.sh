#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Build on macOS 13 or newer." >&2
  exit 1
fi

project_dir="$(cd "$(dirname "$0")" && pwd)"
application_dir="${HOME}/Applications/BlockKeys.app"
mkdir -p "${application_dir}/Contents/MacOS"
swiftc -O -framework AppKit -framework IOKit \
  "${project_dir}"/Sources/*.swift \
  -o "${application_dir}/Contents/MacOS/BlockKeys"
cp "${project_dir}/Info.plist" "${application_dir}/Contents/Info.plist"
codesign --force --sign - "${application_dir}"
open "${application_dir}"
echo "Installed in ${application_dir}. Enable Accessibility permission when prompted."
