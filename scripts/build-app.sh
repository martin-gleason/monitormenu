#!/bin/zsh
# F1-T6: build a release binary and wrap it in a .app bundle, ad-hoc signed with hardened runtime.
#   scripts/build-app.sh            -> build/SwitchBar.app
#   scripts/build-app.sh --install  -> also copies to ~/Applications/SwitchBar.app and links switchctl
# App Intents metadata (FR9): SwiftPM on this toolchain emits .swiftconstvalues; Xcode's
# appintentsmetadataprocessor turns them into Contents/Resources/Metadata.appintents, which is
# what Shortcuts and Siri read. Without that directory the intents compile but never appear.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/SwitchBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SwitchBar "$APP/Contents/MacOS/SwitchBar"
cp .build/release/switchctl "$APP/Contents/MacOS/switchctl"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# --- App Intents metadata -------------------------------------------------------------
TOOLCHAIN=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
SDK=$(xcrun --show-sdk-path --sdk macosx)
XCV=$(xcodebuild -version | awk '/Build version/ {print $3}')
CONST=$(find .build/out -path "*Release*" -name "SwitchBar-primary.swiftconstvalues" | head -1)
if [[ -z "$CONST" ]]; then echo "no .swiftconstvalues for SwitchBar — App Intents metadata skipped" >&2; exit 1; fi
mkdir -p build/appintents
ls Sources/SwitchBar/*.swift | sed "s|^|$PWD/|" > build/appintents/sources.txt
echo "$PWD/$CONST" > build/appintents/constvals.txt
"$TOOLCHAIN/usr/bin/appintentsmetadataprocessor" \
  --output "$APP/Contents/Resources" \
  --toolchain-dir "$TOOLCHAIN" \
  --module-name SwitchBar \
  --sdk-root "$SDK" \
  --xcode-version "$XCV" \
  --platform-family macOS \
  --deployment-target 14.0 \
  --target-triple arm64-apple-macos14.0 \
  --source-file-list build/appintents/sources.txt \
  --swift-const-vals-list build/appintents/constvals.txt \
  --binary-file "$APP/Contents/MacOS/SwitchBar" \
  --force --deployment-aware-processing --no-app-shortcuts-localization 2>&1 | grep -vE "^$" || true
test -d "$APP/Contents/Resources/Metadata.appintents" && echo "App Intents metadata: $(ls "$APP/Contents/Resources/Metadata.appintents" | tr '\n' ' ')" || { echo "Metadata.appintents missing" >&2; exit 1; }

# Hardened runtime, ad-hoc identity. Replace "-" with a Developer ID to notarize.
codesign --force --options runtime --entitlements Resources/SwitchBar.entitlements --sign - "$APP/Contents/MacOS/switchctl"
codesign --force --options runtime --entitlements Resources/SwitchBar.entitlements --sign - "$APP"
echo "Built $APP"
if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  osascript -e 'tell application "SwitchBar" to quit' >/dev/null 2>&1 || true
  rm -rf ~/Applications/SwitchBar.app
  ditto "$APP" ~/Applications/SwitchBar.app
  echo "Installed ~/Applications/SwitchBar.app"
  if [[ -d /opt/homebrew/bin ]]; then ln -sf ~/Applications/SwitchBar.app/Contents/MacOS/switchctl /opt/homebrew/bin/switchctl && echo "Linked /opt/homebrew/bin/switchctl"; fi
fi
