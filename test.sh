#!/bin/zsh
# Pixel-equivalence test: new overlay writes exactly the same EDR pixels as the original BrightXDR.
# (The white-screen fix itself has to be checked by eye: screenshots can't see the overlay without
#  screen-recording permission. Use "Headroom Lab.app" and the flash test in FlashTest/.)
set -euo pipefail
cd "${0:A:h}"
WORK="build/testtmp"
rm -rf "$WORK"; mkdir -p "$WORK"
FLAGS=(-module-cache-path "$WORK/modcache")
OVERLAY=$(Support/make_overlay.sh "$PWD/Support" "$WORK/vfs.yaml")
[[ -n "$OVERLAY" ]] && FLAGS+=(-vfsoverlay "$OVERLAY" -Xcc -ivfsoverlay -Xcc "$OVERLAY")
swiftc "${FLAGS[@]}" -o "$WORK/pixeltest" Compare/Overlay.swift Tests/PixelEquivalence/main.swift
set +e; "$WORK/pixeltest"; RC=$?; set -e
rm -rf "$WORK"
exit $RC
