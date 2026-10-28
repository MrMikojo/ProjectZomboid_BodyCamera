#!/usr/bin/env bash
# Build 42 loads mods from <mod>/42/ (+ <mod>/common/) instead of <mod>/media.
# Run this after editing anything under Contents/mods/BodyCam/media to refresh the B42 copy.
set -euo pipefail
MOD="$(cd "$(dirname "$0")/../Contents/mods/BodyCam" && pwd)"
rm -rf "$MOD/42"
mkdir -p "$MOD/42" "$MOD/common"
cp -r "$MOD/media" "$MOD/42/media"
{ cat "$MOD/mod.info"; echo "versionMin=42.0.0"; } > "$MOD/42/mod.info"
echo "Synced B42 copy into $MOD/42"
