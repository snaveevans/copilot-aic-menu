#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
app="dist/CopilotAICMenu.app"
archive="dist/CopilotAICMenu-macos-universal.zip"
[[ -d "$app" ]] || { echo "Build the app first with UNIVERSAL=1 ./scripts/build-app.sh" >&2; exit 1; }
[[ "$(lipo -archs "$app/Contents/MacOS/CopilotAICMenu")" == *arm64* &&
   "$(lipo -archs "$app/Contents/MacOS/CopilotAICMenu")" == *x86_64* ]] || {
  echo "Release must contain both arm64 and x86_64" >&2; exit 1;
}

rm -f "$archive"
ditto -c -k --keepParent "$app" "$archive"
(cd dist && shasum -a 256 "${archive##*/}" > SHA256SUMS.txt)
printf 'Packaged %s\n' "$archive"
