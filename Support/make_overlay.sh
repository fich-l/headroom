#!/bin/zsh
# Writes a clang/swiftc VFS overlay mapping <CarbonCore/Script.h> to Support/Script.h.
# Only needed when the installed SDK is missing that header (damaged CLT install).
# Usage: make_overlay.sh <support-dir> <out.yaml>   (prints out path if an overlay is needed)
SDK=$(xcrun --show-sdk-path)
REAL=$(cd "$SDK" && pwd -P)
CC="System/Library/Frameworks/CoreServices.framework/Frameworks/CarbonCore.framework"
[[ -f "$REAL/$CC/Versions/A/Headers/Script.h" ]] && exit 0
roots=""
for base in "$SDK" "$REAL"; do
  for sub in Headers Versions/A/Headers Versions/Current/Headers; do
    roots+="{ \"type\": \"directory\", \"name\": \"$base/$CC/$sub\", \"contents\": [ { \"type\": \"file\", \"name\": \"Script.h\", \"external-contents\": \"$1/Script.h\" } ] },"
  done
done
print -r -- "{ \"version\": 0, \"case-sensitive\": \"false\", \"roots\": [ ${roots%,} ] }" > "$2"
echo "$2"
