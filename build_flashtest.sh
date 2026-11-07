#!/bin/zsh
# Builds "FlashTest/XDR Flash Test.app". Rebuilding changes the code signature, so macOS forgets
# its Screen Recording + Accessibility permissions → only rebuild when really necessary.
set -euo pipefail
cd "${0:A:h}"
APP="FlashTest/XDR Flash Test.app"
if [[ -d "$APP" && "${1:-}" != "--force" ]]; then
  echo "Already built (use --force to rebuild; permissions must then be granted again)."; exit 0
fi
WORK="FlashTest/tmp"
rm -rf "$APP" "$WORK"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$WORK"
FLAGS=(-module-cache-path "$WORK/modcache")
OVERLAY=$(Support/make_overlay.sh "$PWD/Support" "$WORK/vfs.yaml")
[[ -n "$OVERLAY" ]] && FLAGS+=(-vfsoverlay "$OVERLAY" -Xcc -ivfsoverlay -Xcc "$OVERLAY")
swiftc "${FLAGS[@]}" -O -target arm64-apple-macos14.0 -o "$APP/Contents/MacOS/XDRFlashTest" FlashTest/main.swift
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>XDR Flash Test</string>
  <key>CFBundleIdentifier</key><string>de.fichl.BrightXDR.FlashTest</string>
  <key>CFBundleExecutable</key><string>XDRFlashTest</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force --sign - "$APP"
rm -rf "$WORK"
echo "✓ Built $APP"
