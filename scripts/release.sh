#!/bin/zsh
# Created: 2026-10-30 09:50 -05:00 · Edited: 2026-10-30 09:53 -05:00
# C6: package a release. Builds and signs the app (scripts/build-app.sh), wraps it in a compressed
# disk image with an Applications link, signs the image, prints its SHA-256.
#   scripts/release.sh                        -> dist/MonitorMenu-<version>.dmg
#   scripts/release.sh --notarize             -> also notarizes and staples the app and the image
#                                                (keychain profile $NOTARY_PROFILE, default "MonitorMenu",
#                                                 made once with: xcrun notarytool store-credentials MonitorMenu)
#   scripts/release.sh --update-cask          -> writes version and sha256 into Casks/monitormenu.rb
# Without --notarize the image opens on this Mac only; Gatekeeper on any other Mac refuses an
# unnotarized Developer ID app, and the last lines say so. The published release is always notarized.
set -euo pipefail
cd "$(dirname "$0")/.."
NOTARIZE=0; UPDATE_CASK=0
for a in "$@"; do
  case "$a" in
    --notarize) NOTARIZE=1 ;;
    --update-cask) UPDATE_CASK=1 ;;
    *) echo "usage: scripts/release.sh [--notarize] [--update-cask]" >&2; exit 2 ;;
  esac
done
PROFILE="${NOTARY_PROFILE:-MonitorMenu}"

scripts/build-app.sh
APP=build/MonitorMenu.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
CORE=$(grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' Sources/MonitorCore/MonitorCore.swift | head -1 | tr -d '"')
if [[ "$VERSION" != "$CORE" ]]; then
  echo "error: Info.plist says $VERSION but MonitorCore.version says $CORE; make them agree before releasing" >&2; exit 1
fi
# No early `exit` in the awk: with pipefail, closing the pipe early makes codesign fail with SIGPIPE.
IDENTITY=$(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority=Developer ID Application/ && !seen {print $2; seen=1}')
if [[ -z "$IDENTITY" ]]; then echo "error: the bundle is not Developer ID signed; a release cannot be ad hoc" >&2; exit 1; fi

mkdir -p dist
NAME="MonitorMenu-$VERSION"
DMG="dist/$NAME.dmg"
rm -f "$DMG" "dist/$NAME.zip"

if (( NOTARIZE )); then
  # The app first, so the bundle inside the image carries its own staple and opens offline.
  ditto -c -k --keepParent "$APP" "dist/$NAME.zip"
  echo "Notarizing the app (profile $PROFILE)…"
  xcrun notarytool submit "dist/$NAME.zip" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "dist/$NAME.zip"
fi

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/monitormenu-stage.XXXXXX")
ditto "$APP" "$STAGE/MonitorMenu.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "MonitorMenu $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if (( NOTARIZE )); then
  echo "Notarizing the image…"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "Built $DMG"
echo "sha256 $SHA"

if (( UPDATE_CASK )); then
  CASK=Casks/monitormenu.rb
  sed -i '' -E "s/^  version \"[^\"]*\"/  version \"$VERSION\"/; s/^  sha256 \"[^\"]*\"/  sha256 \"$SHA\"/" "$CASK"
  grep -E '^  (version|sha256) ' "$CASK"
fi

# Gatekeeper's verdict, as another Mac would give it. Informational: the exit code is the build's.
echo "Gatekeeper:"
spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | sed 's/^/  /' || true
spctl -a -vv "$APP" 2>&1 | sed 's/^/  /' || true
if (( ! NOTARIZE )); then
  echo "NOT NOTARIZED: this image opens on this Mac only. Run with --notarize before publishing (needs the keychain profile; see docs/plans/00-register.md O16)."
fi
