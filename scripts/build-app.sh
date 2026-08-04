#!/usr/bin/env bash
# Assemble the distributable dist/Lit.app: a universal (arm64 + x86_64)
# release build of mac-app/, with dashboard.html and the version from
# VERSION baked into Info.plist. Distinct from mac-app/Scripts/build-app.sh,
# which is for local dev/testing (native-arch only, no version stamping).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/Lit.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION" 2>/dev/null || echo "0.0.1")"
MAC_APP="$ROOT/mac-app"
SWIFT_CONFIG="${SWIFT_CONFIG:-release}"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

# Universal binary — a plain release build on Apple Silicon CI would
# silently be arm64-only, breaking Intel Macs entirely rather than just
# running slower.
if [[ "$SWIFT_CONFIG" == "release" ]]; then
  ( cd "$MAC_APP" && swift build -c release --arch arm64 --arch x86_64 )
  SWIFT_BIN="$MAC_APP/.build/apple/Products/Release/Lit"
else
  ( cd "$MAC_APP" && swift build -c "$SWIFT_CONFIG" )
  SWIFT_BIN="$MAC_APP/.build/$SWIFT_CONFIG/Lit"
fi
cp "$SWIFT_BIN" "$MACOS/Lit"
chmod +x "$MACOS/Lit"

cp "$MAC_APP/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$MAC_APP/Resources/dashboard.html" "$RES/dashboard.html"

if [[ -d "$MAC_APP/Resources/vendor" ]]; then
  cp -R "$MAC_APP/Resources/vendor" "$RES/vendor"
fi

plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$CONTENTS/Info.plist"

# Ad-hoc sign: LSUIElement / MenuBarExtra need a real bundle identity to
# behave reliably. No Developer ID yet, so this is local-only (unsigned
# for Gatekeeper purposes — see the release notes note about right-click Open).
codesign --force --deep --sign - "$APP"

echo "Built: $APP (v${VERSION})"
