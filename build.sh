#!/bin/bash
# Builds build/ChromeProfileBar.app. `./build.sh install` also copies it to /Applications
# and restarts it.
#
# Signing: uses $CODESIGN_IDENTITY (default "ChromeProfileBar Dev", see
# scripts/make-signing-cert.sh). A stable identity + fixed bundle id keep the TCC grants
# (Automation, Accessibility) across rebuilds; the ad-hoc fallback gets re-prompted.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID=dev.cuongnb.ChromeProfileBar
IDENTITY="${CODESIGN_IDENTITY:-ChromeProfileBar Dev}"
APP=build/ChromeProfileBar.app

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/ChromeProfileBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ChromeProfileBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"  # regenerate: swift scripts/make-icon.swift

if security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
  echo "warning: signing identity \"$IDENTITY\" not found; signing ad-hoc." >&2
  echo "         Permissions will be asked again after every rebuild. Run scripts/make-signing-cert.sh." >&2
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
fi
codesign --verify "$APP"
codesign -dr - "$APP" 2>&1 | grep designated
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x ChromeProfileBar && sleep 0.5 || true
  rm -rf /Applications/ChromeProfileBar.app
  cp -R "$APP" /Applications/
  open /Applications/ChromeProfileBar.app
  echo "Installed /Applications/ChromeProfileBar.app"
fi
