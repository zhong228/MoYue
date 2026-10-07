#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

PROJECT="Yuedu-Reader.xcodeproj"
SCHEME="Yuedu-Reader"
VERSION="${1:-1.0.0}"

echo "Building $SCHEME (unsigned) for iOS device, version $VERSION ..."
mkdir -p build

# GoogleService-Info.plist is required by the Xcode project but is gitignored
# (contains Firebase secrets). Generate a well-formed placeholder so the build
# can proceed; runtime Firebase features degrade gracefully when keys are absent.
if [ ! -f "GoogleService-Info.plist" ]; then
  cat > GoogleService-Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CLIENT_ID</key>
	<string>placeholder-client-id</string>
	<key>REVERSED_CLIENT_ID</key>
	<string>com.googleusercontent.apps.placeholder</string>
	<key>API_KEY</key>
	<string>placeholder-api-key</string>
	<key>GCM_SENDER_ID</key>
	<string>0</string>
	<key>PLIST_VERSION</key>
	<string>1</string>
	<key>BUNDLE_ID</key>
	<string>com.zhangruilin.yuedureader</string>
	<key>PROJECT_ID</key>
	<string>moyue-placeholder</string>
	<key>STORAGE_BUCKET</key>
	<string>moyue-placeholder.appspot.com</string>
	<key>IS_ADS_ENABLED</key>
	<false/>
	<key>IS_ANALYTICS_ENABLED</key>
	<false/>
	<key>IS_APPINVITE_ENABLED</key>
	<true/>
	<key>IS_GCM_ENABLED</key>
	<true/>
	<key>GOOGLE_APP_ID</key>
	<string>1:0:ios:placeholder</string>
</dict>
</plist>
PLIST
  echo "Generated placeholder GoogleService-Info.plist (gitignored, not committed)"
fi

# 1. Release build without code signing (device generic destination)
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_COMPILATION_MODE=incremental \
  OTHER_SWIFT_FLAGS="-Xfrontend -typecheck-timeout 0" \
  build > build/xcodebuild.log 2>&1 || {
    echo "xcodebuild FAILED (tail of log):"
    tail -120 build/xcodebuild.log
    exit 1
  }

# 2. Locate built .app
APP="$(find build/DerivedData/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' -type d | head -1)"
if [ -z "$APP" ]; then
  echo "ERROR: .app not found in build products"
  exit 1
fi
echo "App bundle: $APP"

# 3. Assemble unsigned IPA (standard Payload layout)
rm -rf build/unsigned build/MoYue-*.ipa
mkdir -p build/unsigned/Payload
cp -R "$APP" build/unsigned/Payload/
cd build/unsigned
zip -qry "../MoYue-v${VERSION}.ipa" Payload
cd "$PROJECT_DIR"

echo "IPA created: $(pwd)/build/MoYue-v${VERSION}.ipa"
ls -lh "build/MoYue-v${VERSION}.ipa"