#!/bin/zsh
# F1-T6: build a release binary and wrap it in a .app bundle, ad-hoc signed with hardened runtime.
#   scripts/build-app.sh            -> build/MonitorMenu.app
#   scripts/build-app.sh --install  -> also copies to ~/Applications/MonitorMenu.app and links monitorctl
# App Intents metadata (FR9): SwiftPM on this toolchain emits .swiftconstvalues; Xcode's
# appintentsmetadataprocessor turns them into Contents/Resources/Metadata.appintents, which is
# what Shortcuts and Siri read. Without that directory the intents compile but never appear.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/MonitorMenu.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MonitorMenu "$APP/Contents/MacOS/MonitorMenu"
cp .build/release/monitorctl "$APP/Contents/MacOS/monitorctl"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Platform and SDK keys Xcode writes and SwiftPM does not. appintentsd and LaunchServices read them
# (defect A3 bisect, 2026-10-22: an Xcode-built control app carries them; ours did not).
SDKV=$(xcrun --show-sdk-version --sdk macosx); SDKB=$(xcrun --show-sdk-build-version --sdk macosx); XCB=$(xcodebuild -version | awk '/Build version/ {print $3}'); XCV=$(xcodebuild -version | awk '/^Xcode/ {gsub(/\./,"",$2); printf "%04d", $2*10}')
PB=/usr/libexec/PlistBuddy; IP="$APP/Contents/Info.plist"
$PB -c "Add :CFBundleInfoDictionaryVersion string 6.0" -c "Add :CFBundleSupportedPlatforms array" -c "Add :CFBundleSupportedPlatforms:0 string MacOSX" \
    -c "Add :DTPlatformName string macosx" -c "Add :DTPlatformVersion string $SDKV" -c "Add :DTSDKName string macosx$SDKV" -c "Add :DTSDKBuild string $SDKB" \
    -c "Add :DTPlatformBuild string $SDKB" -c "Add :DTXcode string $XCV" -c "Add :DTXcodeBuild string $XCB" -c "Add :DTCompiler string com.apple.compilers.llvm.clang.1_0" \
    -c "Add :BuildMachineOSBuild string $(sw_vers -buildVersion)" "$IP" >/dev/null

# --- App Intents metadata -------------------------------------------------------------
TOOLCHAIN=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain
SDK=$(xcrun --show-sdk-path --sdk macosx)
XCV=$(xcodebuild -version | awk '/Build version/ {print $3}')
CONST=$(find .build/out -path "*Release*" -name "MonitorMenu-primary.swiftconstvalues" | head -1)
if [[ -z "$CONST" ]]; then echo "no .swiftconstvalues for MonitorMenu — App Intents metadata skipped" >&2; exit 1; fi
mkdir -p build/appintents
ls Sources/MonitorMenu/*.swift | sed "s|^|$PWD/|" > build/appintents/sources.txt
echo "$PWD/$CONST" > build/appintents/constvals.txt
"$TOOLCHAIN/usr/bin/appintentsmetadataprocessor" \
  --output "$APP/Contents/Resources" \
  --toolchain-dir "$TOOLCHAIN" \
  --module-name MonitorMenu \
  --sdk-root "$SDK" \
  --xcode-version "$XCV" \
  --platform-family macOS \
  --deployment-target 14.0 \
  --target-triple arm64-apple-macos14.0 \
  --bundle-identifier dev.marty.MonitorMenu \
  --source-file-list build/appintents/sources.txt \
  --swift-const-vals-list build/appintents/constvals.txt \
  --binary-file "$APP/Contents/MacOS/MonitorMenu" \
  --force --compile-time-extraction --deployment-aware-processing --no-app-shortcuts-localization 2>&1 | grep -vE "^$" || true
test -d "$APP/Contents/Resources/Metadata.appintents" && echo "App Intents metadata: $(ls "$APP/Contents/Resources/Metadata.appintents" | tr '\n' ' ')" || { echo "Metadata.appintents missing" >&2; exit 1; }

# Hardened runtime. Signs with the first "Developer ID Application" identity in the keychain when
# there is one (App Intents are only surfaced to Shortcuts for apps with a real team identity —
# defect A3, 2026-10-21), else ad hoc. Override with SIGN_IDENTITY=- or a certificate name.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
echo "Signing as: $IDENTITY"
codesign --force --options runtime --timestamp=none --entitlements Resources/MonitorMenu.entitlements --sign "$IDENTITY" "$APP/Contents/MacOS/monitorctl"
codesign --force --options runtime --timestamp=none --entitlements Resources/MonitorMenu.entitlements --sign "$IDENTITY" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
echo "Built $APP"
if [[ "${1:-}" == "--install" ]]; then
  mkdir -p ~/Applications
  osascript -e 'tell application "MonitorMenu" to quit' >/dev/null 2>&1 || true
  rm -rf ~/Applications/MonitorMenu.app
  ditto "$APP" ~/Applications/MonitorMenu.app
  xattr -dr com.apple.quarantine ~/Applications/MonitorMenu.app 2>/dev/null || true
  # One LaunchServices registration, the installed one: a second (the build/ copy) confuses discovery.
  LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  "$LSR" -u "$APP" >/dev/null 2>&1 || true
  "$LSR" -f ~/Applications/MonitorMenu.app >/dev/null 2>&1 || true
  echo "Installed ~/Applications/MonitorMenu.app"
  if [[ -d /opt/homebrew/bin ]]; then ln -sf ~/Applications/MonitorMenu.app/Contents/MacOS/monitorctl /opt/homebrew/bin/monitorctl && echo "Linked /opt/homebrew/bin/monitorctl"; fi
fi
