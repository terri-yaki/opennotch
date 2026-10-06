#!/bin/bash
# Builds OpenNotch and wraps it into build/OpenNotch.app
# Requires macOS 14+ and Xcode or the Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

echo "Building (release)..."
swift build -c release

BIN="$(swift build -c release --show-bin-path)/OpenNotch"
APP="build/OpenNotch.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/OpenNotch"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc sign so macOS will run it locally and "Launch at Login" can register.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: codesign failed (app may still run)"

echo "Done: $APP"
echo "Run it with:  open $APP"
