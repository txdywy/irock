#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT="$SCRIPT_DIR/irock-macOS.xcodeproj"
BUILD_DIR="$SCRIPT_DIR/build/unsigned"
DERIVED_DATA="$BUILD_DIR/DerivedData"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme irockMacApp \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/Debug/irockMacApp.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Expected app bundle not found: $APP_PATH" >&2
  exit 1
fi

cp -R "$APP_PATH" "$BUILD_DIR/irockMacApp.app"
printf '%s\n' "$BUILD_DIR/irockMacApp.app"
