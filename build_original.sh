#!/bin/zsh
# Builds the untouched upstream starkdmi/BrightXDR (Original/BrightXDR, unmodified) as
# "build/BrightXDR Original.app" — reference for the A/B test.
set -euo pipefail
cd "${0:A:h}"
APP="build/BrightXDR Original.app"
WORK="build/origtmp"
rm -rf "$APP" "$WORK"
mkdir -p "$APP/Contents/MacOS" "$WORK"
FLAGS=(-module-cache-path "$WORK/modcache")
OVERLAY=$(Support/make_overlay.sh "$PWD/Support" "$WORK/vfs.yaml")
[[ -n "$OVERLAY" ]] && FLAGS+=(-vfsoverlay "$OVERLAY" -Xcc -ivfsoverlay -Xcc "$OVERLAY")
SRC=(Original/BrightXDR/main.swift Original/BrightXDR/AppDelegate.swift Original/BrightXDR/MetalView.swift)
swiftc "${FLAGS[@]}" -O -target arm64-apple-macos13.1 -o "$WORK/a" $SRC
swiftc "${FLAGS[@]}" -O -target x86_64-apple-macos13.1 -o "$WORK/x" $SRC
lipo -create "$WORK/a" "$WORK/x" -output "$APP/Contents/MacOS/BrightXDR"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>BrightXDR</string>
<key>CFBundleIdentifier</key><string>com.starkdmi.BrightXDR</string>
<key>CFBundleName</key><string>BrightXDR</string>
<key>CFBundleDisplayName</key><string>Bright XDR</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.1</string>
<key>LSUIElement</key><true/>
</dict></plist>
PL
codesign --force --sign - --entitlements Original/BrightXDR/BrightXDR.entitlements "$APP"
rm -rf "$WORK"
echo "✓ Built $APP"
