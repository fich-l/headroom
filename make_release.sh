#!/bin/zsh
# Builds Headroom and packs it as build/Headroom.zip (the asset to attach to a GitHub release).
set -euo pipefail
cd "${0:A:h}"
./build.sh
rm -f build/Headroom.zip
ditto -c -k --sequesterRsrc --keepParent "build/Headroom.app" "build/Headroom.zip"
shasum -a 256 build/Headroom.zip
echo "✓ build/Headroom.zip"
