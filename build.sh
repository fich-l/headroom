#!/bin/zsh
# Builds "Headroom.app" with only the Xcode Command Line Tools (no Xcode needed).
set -euo pipefail
cd "${0:A:h}"

APP="build/Headroom.app"
WORK="build/tmp"
rm -rf "$APP" "$WORK"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$WORK/AppIcon.iconset"

# Work around a damaged CLT SDK (missing CarbonCore/Script.h) if necessary.
FLAGS=(-module-cache-path "$WORK/modcache")
OVERLAY=$(Support/make_overlay.sh "$PWD/Support" "$WORK/vfs.yaml")
[[ -n "$OVERLAY" ]] && FLAGS+=(-vfsoverlay "$OVERLAY" -Xcc -ivfsoverlay -Xcc "$OVERLAY")

echo "→ Rendering icon"
swiftc "${FLAGS[@]}" -o "$WORK/make_icon" Icon/make_icon.swift
"$WORK/make_icon" "$WORK/icon_1024.png" >/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon_1024.png" --out "$WORK/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$WORK/icon_1024.png" --out "$WORK/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$WORK/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "→ Compiling"
swiftc "${FLAGS[@]}" -O -target arm64-apple-macos13.0 -o "$WORK/Headroom-arm64" Sources/*.swift
swiftc "${FLAGS[@]}" -O -target x86_64-apple-macos13.0 -o "$WORK/Headroom-x86_64" Sources/*.swift
lipo -create "$WORK/Headroom-arm64" "$WORK/Headroom-x86_64" -output "$APP/Contents/MacOS/Headroom"

cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "→ Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"
rm -rf "$WORK"
echo "✓ Built $APP"
