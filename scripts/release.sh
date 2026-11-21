#!/bin/bash
# Builds Handwritten for sharing (no paid Apple account needed):
#   dist/Handwritten-<version>.dmg  — drag-to-Applications installer
#   dist/Handwritten-<version>.zip  — plain zip of the app
# The app is ad-hoc signed (free). Recipients click "Open Anyway" once (see README).
# Usage: ./scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null && xcodegen generate >/dev/null

VERSION=$(grep 'MARKETING_VERSION' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
OUT=build-release            # separate from ./build so your dev copy isn't touched
rm -rf "$OUT" dist
mkdir -p dist

echo "Building Handwritten $VERSION (Apple Silicon + Intel)…"
xcodebuild -project Handwritten.xcodeproj -scheme Handwritten -configuration Release \
  -derivedDataPath "$OUT" CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM="" \
  ONLY_ACTIVE_ARCH=NO ARCHS="arm64 x86_64" build | grep -E "error:|BUILD" || true

APP="$OUT/Build/Products/Release/Handwritten.app"
[ -d "$APP" ] || { echo "Build failed"; exit 1; }

# Ad-hoc signature (free). Apple Silicon Macs refuse to run completely unsigned apps.
codesign --force --deep --options runtime --sign - "$APP"
codesign --verify --strict "$APP"
lipo -info "$APP/Contents/MacOS/Handwritten"

# Zip
ditto -c -k --keepParent "$APP" "dist/Handwritten-$VERSION.zip"

# DMG with an Applications shortcut, so installing is just a drag.
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME FIRST.txt" <<'TXT'
Installing Handwritten

1. Drag Handwritten into the Applications folder.
2. Open Applications and double-click Handwritten.
   macOS will say it can't verify the app. Click "Done".
3. Open System Settings > Privacy & Security, scroll down,
   and click "Open Anyway" next to Handwritten. Confirm.
   (Or run this once in Terminal instead of steps 2-3:
    xattr -dr com.apple.quarantine /Applications/Handwritten.app )
4. When Handwritten opens, turn on Accessibility and
   Input Monitoring for it when asked, then click
   "Relaunch Handwritten".

It lives in the menu bar (the pencil icon at the top of the screen).
Escape always stops typing.
TXT
hdiutil create -volname "Handwritten $VERSION" -srcfolder "$STAGE" -ov -format UDZO \
  "dist/Handwritten-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"

ls -lh dist
echo "Done. Share dist/Handwritten-$VERSION.dmg (or the .zip)."
