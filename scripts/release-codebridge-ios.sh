#!/usr/bin/env bash
# Build/export the main Compose client with the personal CodeBridge identity. Never uploads by itself.
set -euo pipefail
cd "$(dirname "$0")/.."
export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 17)}"
VERSION="${VERSION:-2.6.1}"
BUILD_NUMBER="${BUILD_NUMBER:?set BUILD_NUMBER after checking App Store Connect}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'invalid VERSION' >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo 'invalid BUILD_NUMBER' >&2; exit 1; }
OUTPUT="${OUTPUT:-$PWD/_local/releases/codebridge-compose-$VERSION-$BUILD_NUMBER}"
mkdir -p "$OUTPUT"
xcodegen generate --spec iosApp/codebridge-compose.yml
# Reuse the reviewed upstream package pins; a new generated project must not resolve newer SDKs.
PIN_DIR=iosApp/CodeBridgeCompose.xcodeproj/project.xcworkspace/xcshareddata/swiftpm
mkdir -p "$PIN_DIR"
cp iosApp/iosApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved "$PIN_DIR/Package.resolved"
xcodebuild -project iosApp/CodeBridgeCompose.xcodeproj -scheme CodeBridge \
  -configuration Release -destination 'generic/platform=iOS' \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  -archivePath "$OUTPUT/CodeBridge.xcarchive" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive >"$OUTPUT/archive.log" 2>&1 || { tail -n 65 "$OUTPUT/archive.log"; exit 1; }
grep -q 'ARCHIVE SUCCEEDED' "$OUTPUT/archive.log"
python3 scripts/check-ios-push-entitlements.py "$OUTPUT/CodeBridge.xcarchive/Products/Applications/CodeBridge.app" \
  --environment production --bundle-id com.gejiarong.codebridge --team-id 7U83DS2M3Q
xcodebuild -exportArchive -archivePath "$OUTPUT/CodeBridge.xcarchive" \
  -exportOptionsPlist iosApp/ExportOptions-codebridge.plist -exportPath "$OUTPUT/export" \
  >"$OUTPUT/export.log" 2>&1 || { tail -n 65 "$OUTPUT/export.log"; exit 1; }
IPA="$OUTPUT/export/CodeBridge.ipa"
test -f "$IPA"
mkdir -p "$OUTPUT/verified"
ditto -x -k "$IPA" "$OUTPUT/verified"
python3 scripts/check-ios-push-entitlements.py "$OUTPUT/verified/Payload/CodeBridge.app" \
  --environment production --bundle-id com.gejiarong.codebridge --team-id 7U83DS2M3Q
codesign --verify --deep --strict "$OUTPUT/verified/Payload/CodeBridge.app"
shasum -a 256 "$IPA" >"$OUTPUT/ipa.sha256"
echo "Verified IPA: $IPA"
