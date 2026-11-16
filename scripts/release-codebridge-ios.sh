#!/usr/bin/env bash
# Build/export the native SwiftUI multi-Agent client. Never uploads by itself.
set -euo pipefail
cd "$(dirname "$0")/.."
export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 17)}"
[[ "${VERSION:-1.0.0}" = "1.0.0" ]] || { echo 'CodeBridge marketing version is fixed at 1.0.0' >&2; exit 1; }
VERSION=1.0.0
BUILD_NUMBER="${BUILD_NUMBER:-$(TZ=Asia/Shanghai date +%y%m%d%H%M)}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'invalid VERSION' >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[0-9]{10}$ ]] || { echo 'BUILD_NUMBER must use YYMMDDHHmm (Asia/Shanghai)' >&2; exit 1; }
OUTPUT="${OUTPUT:-$PWD/_local/releases/codebridge-native-$VERSION-$BUILD_NUMBER}"
mkdir -p "$OUTPUT"
xcodegen generate --spec iosApp/codebridge.yml
xcodebuild -project iosApp/CodeBridge.xcodeproj -scheme CodeBridge \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$PWD/_local/derived-data/codebridge-release" \
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
python3 - "$OUTPUT/verified/Payload/CodeBridge.app/Info.plist" "$VERSION" "$BUILD_NUMBER" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as stream:
    info = plistlib.load(stream)
assert info.get('CodeBridgeClient') == 'SwiftUI', 'Refusing non-native client: wrong release target'
assert info.get('CFBundleShortVersionString') == sys.argv[2], 'Marketing version mismatch'
assert info.get('CFBundleVersion') == sys.argv[3], 'Build number mismatch'
print('Native SwiftUI release target verified')
PY
shasum -a 256 "$IPA" >"$OUTPUT/ipa.sha256"
echo "Verified IPA: $IPA"
