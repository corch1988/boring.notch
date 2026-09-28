#!/bin/bash
#
# Local-only Release build + install to /Applications.
#
# ENABLE_HARDENED_RUNTIME=NO is required: hardened runtime turns on library
# validation, which rejects the ad-hoc signed embedded frameworks (two ad-hoc
# signatures do not count as the same Team ID) and the app dies in dyld.
# CI signs with a real identity and keeps hardened runtime on — so this stays
# a command-line override, never a project setting.
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$REPO/build/Build/Products/Release/boringNotch.app"
DEST="/Applications/boringNotch.app"

cd "$REPO"
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release \
  -derivedDataPath build ENABLE_HARDENED_RUNTIME=NO build

[ -d "$APP" ] || { echo "Build produced no app at $APP" >&2; exit 1; }

pkill -x boringNotch 2>/dev/null || true

# cp -R merges into an existing bundle instead of replacing it, leaving
# differently-signed leftovers behind, so the old copy has to go first.
if [ -e "$DEST" ]; then
  [ -d "$DEST/Contents/MacOS" ] || { echo "$DEST is not an app bundle, refusing to delete" >&2; exit 1; }
  rm -rf "$DEST"
fi
cp -R "$APP" "$DEST"

echo "Installed $DEST"
echo "Grant Accessibility permission again if prompted — it is tied to the signature."
open "$DEST"
