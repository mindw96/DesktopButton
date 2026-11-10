#!/bin/bash
set -euo pipefail

# Private keys and notarization credentials stay in Keychain.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple Developer team ID}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-OneButtonNotary}"
SPARKLE_ACCOUNT="com.onebutton.desktop"
ARCHIVE="$ROOT/build/OneButton.xcarchive"
EXPORT="$ROOT/build/export"
DIST="$ROOT/dist"
mkdir -p "$DIST" "$ROOT/build"

# Fail before a long build if authentication is unavailable.
xcrun notarytool history --keychain-profile "$NOTARYTOOL_PROFILE" --output-format json > /dev/null
xcodebuild -project OneButton.xcodeproj -scheme OneButton -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build \
  -archivePath "$ARCHIVE" DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGN_STYLE=Manual \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO archive -quiet

python3 - "$ROOT/build/ExportOptions.plist" "$DEVELOPMENT_TEAM" "$SIGN_IDENTITY" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as file:
    plistlib.dump(dict(method='developer-id', signingStyle='manual',
                       teamID=sys.argv[2], signingCertificate=sys.argv[3]), file)
PY
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$ROOT/build/ExportOptions.plist" -quiet

APP="$EXPORT/Folder In Bar.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$BUILD" =~ ^[0-9]+$ ]] || exit 65
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements :- "$APP" > "$ROOT/build/release-entitlements.plist" 2>/dev/null
python3 -E - "$ROOT/build/release-entitlements.plist" "$APP/Contents/MacOS/Folder In Bar" <<'PY'
import plistlib, subprocess, sys
architectures = subprocess.check_output(['lipo', '-archs', sys.argv[2]], text=True).split()
assert {'arm64', 'x86_64'}.issubset(architectures), 'Missing Universal architecture'
with open(sys.argv[1], 'rb') as file:
    entitlements = plistlib.load(file)
assert entitlements.get('com.apple.security.app-sandbox') is True
assert entitlements.get('com.apple.security.network.client') is True
assert not entitlements.get('com.apple.security.cs.disable-library-validation')
assert not entitlements.get('com.apple.security.get-task-allow')
assert not entitlements.get('com.apple.security.files.user-selected.read-write')
PY

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/build/notarization.zip"
xcrun notarytool submit "$ROOT/build/notarization.zip" \
  --keychain-profile "$NOTARYTOOL_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

ZIP="$DIST/FolderInBar-$VERSION.zip"
DMG="$DIST/FolderInBar-$VERSION.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
STAGING=$(mktemp -d "$ROOT/build/dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Folder In Bar.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname 'Folder In Bar' -srcfolder "$STAGING" -format UDZO -ov "$DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
hdiutil verify "$DMG"

SPARKLE_BIN="$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
UPDATE_STAGE=$(mktemp -d "$ROOT/build/appcast.XXXXXX")
trap 'rm -rf "$STAGING" "$UPDATE_STAGE"' EXIT
cp "$ZIP" "$UPDATE_STAGE/"
"$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "https://github.com/mindw96/DesktopButton/releases/download/v$VERSION/" \
  "$UPDATE_STAGE"
cp "$UPDATE_STAGE/appcast.xml" "$DIST/appcast.xml"
python3 "$ROOT/script/verify_appcast.py" "$DIST/appcast.xml" "$ZIP" "$APP"
PUBLIC_KEY=$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p)
[[ "$PUBLIC_KEY" == "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist")" ]]
SIGNATURE=$(python3 - "$DIST/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
print(ET.parse(sys.argv[1]).find('channel/item/enclosure').attrib[
    '{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'])
PY
)
"$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$ZIP" "$SIGNATURE"
cp "$DIST/appcast.xml" "$ROOT/appcast.xml"
(
  cd "$DIST"
  shasum -a 256 "FolderInBar-$VERSION.zip" "FolderInBar-$VERSION.dmg" > SHA256SUMS
)
printf 'Ready: %s\n' "$ZIP" "$DMG" "$DIST/SHA256SUMS" "$ROOT/appcast.xml"
