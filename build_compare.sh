#!/bin/zsh
# Builds "Headroom Lab.app": A/B toggle (untouched original BrightXDR ⇄ Headroom) and the overlay/gamma lab
# driven by the flash test. GPL-3 (contains upstream BrightXDR code), see Compare/LICENSE.
set -euo pipefail
cd "${0:A:h}"

APP="build/Headroom Lab.app"
WORK="build/cmptmp"
rm -rf "$APP" "$WORK"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$WORK"
[[ -f "build/Headroom.app/Contents/Resources/AppIcon.icns" ]] || ./build.sh
cp "build/Headroom.app/Contents/Resources/AppIcon.icns" "$APP/Contents/Resources/"

FLAGS=(-module-cache-path "$WORK/modcache")
OVERLAY=$(Support/make_overlay.sh "$PWD/Support" "$WORK/vfs.yaml")
[[ -n "$OVERLAY" ]] && FLAGS+=(-vfsoverlay "$OVERLAY" -Xcc -ivfsoverlay -Xcc "$OVERLAY")

SRC=(Sources/Gamma.swift Compare/Overlay.swift Compare/main.swift Compare/GammaSpec.swift Compare/Original/MetalView.swift)
echo "→ Compiling"
swiftc "${FLAGS[@]}" -O -target arm64-apple-macos13.0 -o "$WORK/a" $SRC
swiftc "${FLAGS[@]}" -O -target x86_64-apple-macos13.0 -o "$WORK/x" $SRC
lipo -create "$WORK/a" "$WORK/x" -output "$APP/Contents/MacOS/HeadroomLab"

cp Resources/Info.plist "$APP/Contents/Info.plist"
plutil -replace CFBundleName -string "Headroom Lab" "$APP/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "Headroom Lab" "$APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "de.fichl.Headroom.Lab" "$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "HeadroomLab" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP"
rm -rf "$WORK"
echo "✓ Built $APP"
