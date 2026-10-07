#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

PROJECT="Yuedu-Reader.xcodeproj"
SCHEME="Yuedu-Reader"
VERSION="${1:-1.0.0}"

echo "Building $SCHEME (unsigned) for iOS device, version $VERSION ..."

# 1. Release build without code signing (device generic destination)
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
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