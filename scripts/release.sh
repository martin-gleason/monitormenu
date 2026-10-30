#!/bin/zsh
# Created: 2026-10-30 09:50 -05:00 · Edited: 2026-10-30 10:10 -05:00
# C6: package a release. Builds and signs the app (scripts/build-app.sh), wraps it in a compressed
# disk image with an Applications link, signs the image, prints its SHA-256 and the commit it came from.
#   scripts/release.sh --notarize [--update-cask]   -> dist/MonitorMenu-<version>.dmg, notarized and
#                                                     stapled (app, then image); the cask gets version + sha256
#   scripts/release.sh --dev [--update-cask]        -> local trial: not notarized, dirty tree allowed
# Notarization uses the keychain profile $NOTARY_PROFILE (default "MonitorMenu"), made once with
#   xcrun notarytool store-credentials MonitorMenu
# An image that is not notarized opens only where it carries no quarantine attribute; anything a user
# downloads, or Homebrew installs, is refused by Gatekeeper. So: a release is --notarize, never --dev,
# and --update-cask refuses to write an unnotarized checksum into the tracked cask without --dev.
set -euo pipefail
cd "$(dirname "$0")/.."
NOTARIZE=0; UPDATE_CASK=0; DEV=0
for a in "$@"; do
  case "$a" in
    --notarize) NOTARIZE=1 ;;
    --update-cask) UPDATE_CASK=1 ;;
    --dev) DEV=1 ;;
    *) echo "usage: scripts/release.sh (--notarize | --dev) [--update-cask]" >&2; exit 2 ;;
  esac
done
if (( NOTARIZE == DEV )); then echo "usage: exactly one of --notarize (a release) or --dev (a local trial)" >&2; exit 2; fi
PROFILE="${NOTARY_PROFILE:-MonitorMenu}"

# Pre-flight, before the build so a missing profile or a dirty tree costs seconds, not minutes.
if (( NOTARIZE )); then
  if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    echo "error: no notarytool keychain profile named '$PROFILE'. Run once: xcrun notarytool store-credentials $PROFILE (register O16)" >&2; exit 1
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: the working tree is not clean; a release is built from a commit, so that the tag, the asset and the checksum agree" >&2; exit 1
  fi
fi
HEAD_SHA=$(git rev-parse --short HEAD)

STAGE=""; ZIP=""
cleanup() { [[ -n "$STAGE" ]] && rm -rf "$STAGE"; [[ -n "$ZIP" ]] && rm -f "$ZIP"; return 0; }
trap cleanup EXIT

scripts/build-app.sh
APP=build/MonitorMenu.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
CORE=$(grep -oE '"[0-9]+\.[0-9]+\.[0-9]+"' Sources/MonitorCore/MonitorCore.swift | head -1 | tr -d '"')
if [[ "$VERSION" != "$CORE" ]]; then
  echo "error: Info.plist says $VERSION but MonitorCore.version says $CORE; make them agree before releasing" >&2; exit 1
fi
# Sign the image with the identity's SHA-1 hash, not its name: after a certificate renewal both the
# old and the new certificate can share the name and codesign refuses an ambiguous one.
# No early `exit` in the awk: with pipefail, closing the pipe early makes the producer fail with SIGPIPE.
TEAM=$(codesign -dvv "$APP" 2>&1 | awk -F= '/^TeamIdentifier=/ && !seen {print $2; seen=1}')
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -v t="($TEAM)" '/Developer ID Application/ && index($0, t) && !seen {print $2; seen=1}')
if [[ -z "$IDENTITY" ]]; then echo "error: no Developer ID Application identity for team $TEAM in the keychain; a release cannot be ad hoc" >&2; exit 1; fi

# notarytool exits 0 on a submission that was processed, whatever Apple's verdict. Read the verdict.
notarize() {  # $1 = path
  local out id status
  out=$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait 2>&1) || { echo "$out" >&2; return 1; }
  echo "$out" | sed 's/^/  /'
  id=$(echo "$out" | awk '/^ *id:/ && !seen {print $2; seen=1}')
  status=$(echo "$out" | awk '/^ *status:/ {s=$2} END {print s}')
  if [[ "$status" != "Accepted" ]]; then
    echo "error: notarization of $1 ended '$status'. Apple's log:" >&2
    xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
    return 1
  fi
}

mkdir -p dist
NAME="MonitorMenu-$VERSION"
DMG="dist/$NAME.dmg"
rm -f "$DMG"

if (( NOTARIZE )); then
  # The app first, so the bundle inside the image carries its own staple and opens offline.
  ZIP="dist/$NAME.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Notarizing the app (profile $PROFILE)…"
  notarize "$ZIP"
  xcrun stapler staple "$APP"
fi

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/monitormenu-stage.XXXXXX")
ditto "$APP" "$STAGE/MonitorMenu.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "MonitorMenu $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

if (( NOTARIZE )); then
  echo "Notarizing the image…"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
fi

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
echo "Built $DMG from commit $HEAD_SHA"
echo "sha256 $SHA"

if (( UPDATE_CASK )); then
  CASK=Casks/monitormenu.rb
  STAMP=$(date "+%Y-%m-%d %H:%M %z" | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/')
  sed -i '' -E "s/^  version \"[^\"]*\"/  version \"$VERSION\"/; s/^  sha256 \"[^\"]*\"/  sha256 \"$SHA\"/; 1s/Edited: [0-9: -]+[+-][0-9:]+/Edited: $STAMP/" "$CASK"
  grep -E '^  (version|sha256) ' "$CASK"
  (( DEV )) && echo "DEV: the cask now carries an UNNOTARIZED checksum; do not commit it"
fi

# Gatekeeper's verdict, as another Mac would give it. Informational: the exit code is the build's.
echo "Gatekeeper:"
spctl -a -t open --context context:primary-signature -vv "$DMG" 2>&1 | sed 's/^/  /' || true
spctl -a -vv "$APP" 2>&1 | sed 's/^/  /' || true
if (( DEV )); then
  echo "DEV BUILD, NOT NOTARIZED: Gatekeeper refuses this image wherever it carries a quarantine attribute (any download, any Homebrew install). Publish only what --notarize produced."
fi
