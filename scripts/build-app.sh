#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
swift build -c release --product CopilotAICMenu
binary="$(swift build -c release --show-bin-path)/CopilotAICMenu"
app="$PWD/dist/CopilotAICMenu.app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/CopilotAICMenu"
cp packaging/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$app"
printf 'Built %s\n' "$app"
