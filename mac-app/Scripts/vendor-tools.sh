#!/usr/bin/env bash
# Regenerates mac-app/Resources/vendor/{adb,libimobiledevice} from the
# current Homebrew install, so the app doesn't need `brew install
# android-platform-tools` / `brew install libimobiledevice` at all.
#
# Run this once whenever those Homebrew formulae are updated and you want
# to refresh the vendored copies (the output is committed to the repo —
# this script is not part of the normal build).
#
# adb is a universal (arm64+x86_64) binary with zero external deps, so it's
# a straight copy. libimobiledevice's tools and their dylib dependencies are
# only built arm64-only by Homebrew, so they're relinked with install_name_tool
# to be relocatable (@executable_path / @loader_path) and re-signed ad-hoc.
# Intel Macs fall back to a Homebrew-installed copy at runtime — see
# PeripheralsMonitor.findBinary.
set -euo pipefail
cd "$(dirname "$0")/.."
VENDOR="Resources/vendor"

command -v adb >/dev/null || { echo "adb not found — brew install android-platform-tools" >&2; exit 1; }
command -v idevice_id >/dev/null || { echo "idevice_id not found — brew install libimobiledevice" >&2; exit 1; }

rm -rf "$VENDOR"
mkdir -p "$VENDOR/adb" "$VENDOR/libimobiledevice/bin" "$VENDOR/libimobiledevice/lib"

# --- adb ---
cp "$(command -v adb)" "$VENDOR/adb/adb"
chmod +w+x "$VENDOR/adb/adb"

# --- libimobiledevice + transitive dylib deps ---
BIN="$VENDOR/libimobiledevice/bin"
LIB="$VENDOR/libimobiledevice/lib"

resolve() { python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$1"; }

cp "$(resolve "$(command -v idevice_id)")" "$BIN/idevice_id"
cp "$(resolve "$(command -v ideviceinfo)")" "$BIN/ideviceinfo"

DYLIBS=(
  libimobiledevice-1.0.6.dylib
  libssl.3.dylib
  libcrypto.3.dylib
  libusbmuxd-2.0.7.dylib
  libimobiledevice-glue-1.0.0.dylib
  libplist-2.0.4.dylib
)
for name in "${DYLIBS[@]}"; do
  found="$(find /opt/homebrew/opt /opt/homebrew/Cellar -name "$name" 2>/dev/null | head -1)"
  [[ -n "$found" ]] || { echo "missing dylib: $name" >&2; exit 1; }
  cp "$(resolve "$found")" "$LIB/$name"
done
chmod -R +w "$BIN" "$LIB"

# Every absolute Homebrew path (both /opt/homebrew/opt/... symlink form and
# the resolved /opt/homebrew/Cellar/... form) that any of these binaries or
# dylibs might reference, mapped to a bundle-relative load path.
homebrew_paths_for() {
  local name="$1" formula="$2"
  find /opt/homebrew/opt/"$formula"/lib /opt/homebrew/Cellar/"$formula"/*/lib \
    -name "$name" 2>/dev/null
}

rewrite_refs() {
  local target="$1" placeholder="$2"
  for pair in \
    "libssl.3.dylib:openssl@3" "libcrypto.3.dylib:openssl@3" \
    "libusbmuxd-2.0.7.dylib:libusbmuxd" \
    "libimobiledevice-glue-1.0.0.dylib:libimobiledevice-glue" \
    "libplist-2.0.4.dylib:libplist"
  do
    local name="${pair%%:*}" formula="${pair##*:}"
    while IFS= read -r old; do
      [[ -n "$old" ]] && install_name_tool -change "$old" "$placeholder/$name" "$target" 2>/dev/null || true
    done < <(homebrew_paths_for "$name" "$formula")
  done
}

for name in "${DYLIBS[@]}"; do
  install_name_tool -id "@loader_path/$name" "$LIB/$name"
done
for name in "${DYLIBS[@]}"; do
  rewrite_refs "$LIB/$name" "@loader_path"
done
rewrite_refs "$BIN/idevice_id" "@executable_path/../lib"
rewrite_refs "$BIN/ideviceinfo" "@executable_path/../lib"

codesign --force --sign - "$VENDOR/adb/adb"
for f in "$LIB"/*.dylib "$BIN"/idevice_id "$BIN"/ideviceinfo; do
  codesign --force --sign - "$f"
done

xattr -rc "$VENDOR" 2>/dev/null || true

echo "Vendored tools written to $VENDOR/"
echo "Verify with: otool -L $BIN/idevice_id"
