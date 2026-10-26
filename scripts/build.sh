#!/bin/sh
# Builds Kilele.app. With --install, copies it to /Applications and opens it.
# Signed with "Kilele Local Signing" if scripts/make-signing-identity.sh has made it (permissions then survive rebuilds),
# otherwise ad-hoc.
set -e
cd "$(dirname "$0")/.."
SIGN=-
security find-certificate -c "Kilele Local Signing" >/dev/null 2>&1 && SIGN="Kilele Local Signing"
swift build -c release
APP=build/Kilele.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Kilele "$APP/Contents/MacOS/Kilele"
cp Support/Info.plist "$APP/Contents/Info.plist"
# Bundle mediaremote-adapter (for what's playing in browsers) if scripts/build-adapter.sh has built it.
ADAPTER=Vendor/mediaremote-adapter
if [ -d "$ADAPTER/build/MediaRemoteAdapter.framework" ]; then
  mkdir -p "$APP/Contents/Resources/MediaRemoteAdapter"
  cp -R "$ADAPTER/build/MediaRemoteAdapter.framework" "$APP/Contents/Resources/MediaRemoteAdapter/"
  cp "$ADAPTER/bin/mediaremote-adapter.pl" "$ADAPTER/LICENSE" "$APP/Contents/Resources/MediaRemoteAdapter/"
  codesign --force --sign "$SIGN" "$APP/Contents/Resources/MediaRemoteAdapter/MediaRemoteAdapter.framework"
  echo "Bundled mediaremote-adapter"
else
  echo "mediaremote-adapter not built (scripts/build-adapter.sh): Music and Spotify only"
fi
codesign --force --sign "$SIGN" "$APP"
echo "Built $APP (signed: $SIGN)"
if [ "$1" = "--install" ]; then
  pkill -x Kilele 2>/dev/null || true
  rm -rf /Applications/Kilele.app
  cp -R "$APP" /Applications/Kilele.app
  open /Applications/Kilele.app
  echo "Installed and opened /Applications/Kilele.app"
fi
