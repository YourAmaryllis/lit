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

# LSUIElement / MenuBarExtra need a real bundle identity to behave reliably,
# so this always signs at least ad-hoc. Set CODESIGN_IDENTITY (e.g.
# "Developer ID Application: Your Name (TEAMID)" — see `security
# find-identity -v -p codesigning`) to sign for real distribution instead;
# see the "Signing & notarization" section in the README for the full path
# to notarized, Gatekeeper-clean builds.
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "Signing with: $CODESIGN_IDENTITY"

  # Vendored adb/libimobiledevice binaries are nested Mach-O executables and
  # dylibs, not just opaque resources — notarization inspects each one, so
  # each needs its own hardened-runtime signature under the same identity
  # (vendor-tools.sh only ad-hoc-signs them, which fails notarization).
  if [[ -d "$RES/vendor" ]]; then
    find "$RES/vendor" -type f \( -perm -111 -o -name '*.dylib' \) -exec \
      codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" {} \;
  fi

  # Signs the bundle (including Contents/MacOS/Lit) in one shot — no --deep,
  # since the vendor binaries above are already signed individually and
  # --deep would try (and needn't) re-sign them itself.
  codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  echo "No CODESIGN_IDENTITY set — ad-hoc signing only (local dev / unsigned distribution)."
  codesign --force --deep --sign - "$APP"
fi

echo "Built: $APP (v${VERSION})"
