#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Local builds default to the host architecture. Releases use UNIVERSAL=1.
version="${VERSION:-0.1.0}"
build_number="${BUILD_NUMBER:-1}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$build_number" =~ ^[0-9]+$ ]]; then
  echo 'VERSION must be X.Y.Z and BUILD_NUMBER must be numeric' >&2
  exit 1
fi

app="$PWD/dist/CopilotAICMenu.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"

if [[ "${UNIVERSAL:-0}" == 1 ]]; then
  for arch in arm64 x86_64; do
    swift build -c release --triple "${arch}-apple-macosx13.0" --product CopilotAICMenu
  done
  arm="$(swift build -c release --triple arm64-apple-macosx13.0 --show-bin-path)/CopilotAICMenu"
  intel="$(swift build -c release --triple x86_64-apple-macosx13.0 --show-bin-path)/CopilotAICMenu"
  lipo -create "$arm" "$intel" -output "$app/Contents/MacOS/CopilotAICMenu"
else
  swift build -c release --product CopilotAICMenu
  binary="$(swift build -c release --show-bin-path)/CopilotAICMenu"
  cp "$binary" "$app/Contents/MacOS/CopilotAICMenu"
fi

cp packaging/Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources"
cp LICENSE "$app/Contents/Resources/LICENSE"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$app"
else
  # Local/unnotarized builds. macOS Gatekeeper may block downloaded archives.
  codesign --force --sign - --timestamp=none "$app"
fi
codesign --verify --deep "$app"
printf 'Built %s (%s)\n' "$app" "$(lipo -archs "$app/Contents/MacOS/CopilotAICMenu")"
